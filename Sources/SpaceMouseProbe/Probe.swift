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
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(SpaceJuggler.appName).app")
        connection = SpaceJugglerConnection(
            name: "SpaceMouse Probe",
            claim: Claim(apps: [Bundle.main.bundleIdentifier ?? "me.metaebene.SpaceMouseProbe"], raw: true),
            // Run outside its bundle (swift run), it uses whichever Space Juggler runs.
            launcher: FileManager.default.fileExists(atPath: bundled.path) ? .app(bundled) : .none)
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
            problem = version < 4 ? "Space Juggler \(version) is running, which cannot describe devices yet. It hands over to this one's in a moment." : nil
        case .disconnected:
            brokerVersion = nil
        case .holding(let holds):
            self.holds = holds
        case .devices(let devices):
            update(devices)
        case .unavailable(let reason):
            problem = reason
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

    // MARK: - Sending

    func report(_ session: ProbeSession) -> ProbeReport {
        session.report(brokerVersion: brokerVersion, driverRunning: driverRunning)
    }

    /// Opens the issue form with the report in it; when it is too long for a link, it goes to the clipboard and the
    /// form says to paste it.
    func sendToGitHub(_ session: ProbeSession) {
        let json = String(decoding: report(session).json, as: UTF8.self)
        let title = String(format: "Device report: %@ (%04X:%04X)", session.device.name, session.device.vendorID,
                           session.device.productID)
        var components = URLComponents(url: Self.issues, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "template", value: "device-report.yml"), URLQueryItem(name: "title", value: title),
                     URLQueryItem(name: "model", value: session.printedName.isEmpty ? session.device.name : session.printedName)]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        if json.utf8.count < 6000 { items.append(URLQueryItem(name: "report", value: json)) }
        components.queryItems = items
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
