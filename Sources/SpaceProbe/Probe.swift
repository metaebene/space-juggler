import AppKit
import Foundation
import Observation
import SpaceJugglerClient

/// The probe's connection to Space Juggler and a session per attached device (ADR-0006). It claims its own app and
/// raw reports, so it holds the SpaceMouse while it is in front; it never opens a device itself.
@MainActor
@Observable
final class Probe {
    private(set) var sessions: [ProbeSession] = []
    private(set) var holds = false
    private(set) var brokerVersion: Int?
    private(set) var problem: String?
    var selection: String?

    private let connection: SpaceJugglerConnection

    /// The issue form a report goes to (`.github/ISSUE_TEMPLATE/device-report.yml`).
    static let issues = URL(string: "https://github.com/metaebene/space-juggler/issues/new")!

    init() {
        connection = SpaceJugglerConnection(
            name: "Space Probe",
            claim: Claim(apps: [Bundle.main.bundleIdentifier ?? "me.metaebene.SpaceProbe"], raw: true),
            // Run outside its bundle (swift run), it uses whichever Space Juggler runs.
            launcher: .bundledIfPresent)
        connection.onEvent = { [weak self] in self?.handle($0) }
        connection.onReport = { [weak self] bytes, device in
            self?.sessions.first { $0.id == device }?.ingest(bytes)
        }
        connection.start()
    }

    var selected: ProbeSession? { sessions.first { $0.id == selection } ?? sessions.first }

    /// 3Dconnexion's helper holds the devices (ADR-0004): no raw reports.
    var driverRunning: Bool { sessions.contains { $0.device.state == "driver" } }

    private func handle(_ event: SpaceJugglerConnection.Event) {
        switch event {
        case .connected(let version):
            brokerVersion = version
            // A broker of protocol 1 has neither `describe` nor raw reports; the probe's own takes over in a moment.
            problem = connection.brokerProtocolVersion ?? 1 < SpaceJuggler.protocolVersion
                ? String(localized: "An older Space Juggler is running; it hands over to the probe's in a moment.") : nil
        case .disconnected:
            brokerVersion = nil
        case .holding(let holds):
            self.holds = holds
        case .devices(let devices):
            update(devices)
        case .unavailable(let reason):
            problem = Bundle.main.localizedString(forKey: reason, value: reason, table: nil)
        case .axes, .buttons:
            break
        }
    }

    private func update(_ devices: [SpaceMouseDevice]) {
        var kept: [ProbeSession] = []
        for device in devices {
            if let session = sessions.first(where: { $0.id == device.id }) {
                session.device = device
                kept.append(session)
            } else {
                let session = ProbeSession(device: device)
                kept.append(session)
                describe(session)
            }
        }
        sessions = kept
    }

    func describe(_ session: ProbeSession) {
        connection.describe(device: session.id) { description in
            session.description = description
            session.descriptor = HIDReportDescriptor(description.reportDescriptor)
        }
    }

    func setLED(_ on: Bool, _ session: ProbeSession) {
        connection.setLED(on, device: session.id)
    }

    /// Starts the test of a device again from the beginning.
    func restart(_ session: ProbeSession) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
        let fresh = ProbeSession(device: session.device)
        fresh.description = session.description
        fresh.descriptor = session.descriptor
        sessions[index] = fresh
    }

    // MARK: - Report

    /// Where reports are put down: `~/Library/Application Support/Space Probe/Reports`.
    static var reportsFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Space Probe/Reports", isDirectory: true)
    }

    /// Makes the report and puts it down in `reportsFolder`.
    func createReport(_ session: ProbeSession) {
        let report = session.makeReport(brokerVersion: brokerVersion, driverRunning: driverRunning)
        session.report = report
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = String(format: "%@ %04X-%04X %@.json", formatter.string(from: report.date), session.device.vendorID,
                          session.device.productID, session.device.name.replacingOccurrences(of: "/", with: "-"))
        let file = Self.reportsFolder.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: Self.reportsFolder, withIntermediateDirectories: true)
        session.reportFile = (try? report.json.write(to: file)) == nil ? nil : file
        session.step = .report
    }

    /// Puts the report on the clipboard and opens a new issue with the device report form (only title and model in
    /// the link: GitHub refuses long links, the report is pasted).
    func sendToGitHub(_ session: ProbeSession) {
        guard let report = session.report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: report.json, as: UTF8.self), forType: .string)
        let title = String(format: "Device report: %@ (%04X:%04X)", session.device.name, session.device.vendorID,
                           session.device.productID)
        var components = URLComponents(url: Self.issues, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "template", value: "device-report.yml"), URLQueryItem(name: "title", value: title),
                                 URLQueryItem(name: "model", value: session.printedName.isEmpty ? session.device.name : session.printedName)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
