import Foundation
import Observation
import SpaceJugglerClient

/// One test of one device, step by step (ADR-0006): what the probe has seen and been told, and where the user is.
@MainActor
@Observable
final class ProbeSession: Identifiable {
    struct DirectionResult: Equatable {
        var axis: Int
        var sign: Int
        var peak: Int
        var asExpected: Bool
    }

    /// The steps of a test, in order.
    enum Step: Int, CaseIterable, Identifiable, Comparable {
        case start, description, keys, cap, led, label, summary, report
        var id: Int { rawValue }
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        /// The steps shown in the progress bar.
        static let shown: [Step] = [.description, .keys, .cap, .led, .label, .summary]
    }

    let id: String
    var device: SpaceMouseDevice
    var description: DeviceDescription?
    var descriptor: HIDReportDescriptor?
    var step = Step.start

    // Live input, always
    var axes = SpaceMouseAxes.zero
    var heldBits: Set<Int> = []
    var reportsSeen = 0

    // Keys: in the order first pressed, each with what the user says is printed on it
    var keys: [Int] = []
    var labels: [Int: String] = [:]
    var noMoreKeys = false

    // Cap
    var results: [SpaceMouseAxes.Direction: DirectionResult] = [:]
    var ranges: [[Int]] = Array(repeating: [0, 0], count: 6)
    private var candidate: DirectionResult?

    // LED
    var ledLit: Bool?
    var ledWentOut: Bool?

    // Label and notes
    var printedName = ""
    var printedSerial = ""
    var noSerialPrinted = false
    var notes = ""

    // Other reports
    var batteryReports: [[UInt8]] = []
    var otherReports: [UInt8: [UInt8]] = [:]

    /// The report once made, and where it was put down.
    var report: ProbeReport?
    var reportFile: URL?

    init(device: SpaceMouseDevice) {
        id = device.id
        self.device = device
    }

    // MARK: - What the descriptor says

    var fullScale: Int { descriptor?.axisLogicalMaximum ?? device.axisFullScale ?? SpaceMouseAxes.deviceFullScale }
    /// The buttons the descriptor declares (bit = usage − 1).
    var declaredBits: [Int] { descriptor?.buttonUsages.map { $0 - 1 } ?? [] }
    var hasLED: Bool { descriptor?.hasLED ?? device.hasLED ?? true }
    /// The two side buttons, drawn on the SpaceMouse.
    var hasSideButtons: Bool { device.buttons.map { $0.contains(.left) } ?? (declaredBits == [0, 1]) }

    private var model: SpaceMouseModel? {
        SpaceMouseModel.recognise(vendorID: device.vendorID, productID: device.productID, product: device.name,
                                  descriptor: descriptor)
    }

    /// What the catalog calls the key at `bit`, if the model is in it.
    func catalogName(_ bit: Int) -> String? { model?.buttonBits[bit]?.name }

    /// A label to start from: the side of a side button, else the catalog's name of the key.
    func suggestedLabel(_ bit: Int) -> String {
        switch model?.buttonBits[bit] {
        case SpaceMouseButtons.left?: String(localized: "Left button")
        case SpaceMouseButtons.right?: String(localized: "Right button")
        case let button?: button.name
        case nil: ""
        }
    }

    var asked: SpaceMouseAxes.Direction? { SpaceMouseAxes.Direction.allCases.first { results[$0] == nil } }

    // MARK: - Done?

    func isDone(_ step: Step) -> Bool {
        switch step {
        case .start: true
        case .description: description != nil && description?.error == nil
        case .keys:
            keys.allSatisfy { !(labels[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
                && (noMoreKeys || Set(declaredBits).isSubset(of: keys))
        case .cap: asked == nil
        case .led: !hasLED || (ledLit != nil && ledWentOut != nil)
        case .label: !printedName.trimmingCharacters(in: .whitespaces).isEmpty && (noSerialPrinted || !printedSerial.isEmpty)
        case .summary, .report: report != nil
        }
    }

    var next: Step? { Step(rawValue: step.rawValue + 1).flatMap { $0 == .led && !hasLED ? .label : $0 } }
    var previous: Step? { Step(rawValue: step.rawValue - 1).flatMap { $0 == .led && !hasLED ? .cap : $0 } }

    // MARK: - Input reports

    /// Every report updates the drawing; keys count only in the keys step, the cap only in the cap step.
    func ingest(_ bytes: [UInt8]) {
        guard let id = bytes.first else { return }
        reportsSeen += 1
        bytes.withUnsafeBufferPointer { buffer in
            if let bits = SpaceMouseReport.buttonBits(buffer) {
                let now = Set(bits)
                if step == .keys {
                    for bit in now.subtracting(heldBits).sorted() where !keys.contains(bit) {
                        keys.append(bit)
                        labels[bit] = suggestedLabel(bit)
                    }
                }
                heldBits = now
            } else if id == SpaceMouseReport.batteryReportID {
                if batteryReports.last != bytes { batteryReports.append(bytes) }
            } else if SpaceMouseReport.take(buffer, into: &axes) {
                if SpaceMouseReport.completes(buffer) { axesChanged() }
            } else if otherReports[id] == nil {
                otherReports[id] = bytes
            }
        }
    }

    func forgetKeys() {
        keys = []
        labels = [:]
        noMoreKeys = false
    }

    /// Follows the cap through the asked direction: the axis that goes furthest past half the range is what that
    /// direction does; recorded when the cap is back at rest.
    private func axesChanged() {
        let values = axes.all
        for (index, value) in values.enumerated() {
            ranges[index][0] = min(ranges[index][0], value)
            ranges[index][1] = max(ranges[index][1], value)
        }
        guard step == .cap, let asked else { return }
        if let index = values.indices.max(by: { abs(values[$0]) < abs(values[$1]) }), abs(values[index]) > fullScale / 2 {
            let sign = values[index] > 0 ? 1 : -1
            if candidate == nil || abs(values[index]) > candidate!.peak {
                candidate = DirectionResult(axis: index, sign: sign, peak: abs(values[index]),
                                            asExpected: index == asked.axis.index && sign == asked.axis.sign)
            }
        }
        if let found = candidate, values.allSatisfy({ abs($0) < fullScale / 10 }) {
            results[asked] = found
            candidate = nil
        }
    }

    func redoCap() {
        results = [:]
        candidate = nil
    }

    // MARK: - Report

    func makeReport(brokerVersion: Int?, driverRunning: Bool) -> ProbeReport {
        let parsed = descriptor
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        return ProbeReport(
            tool: "SpaceMouse Probe \(SpaceJuggler.version)", date: Date(),
            macOS: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            spaceJuggler: brokerVersion, driverRunning: driverRunning,
            device: .init(
                name: device.name, knowledge: device.knowledge?.rawValue,
                vendorID: String(format: "%04X", device.vendorID), productID: String(format: "%04X", device.productID),
                transport: device.transport, identity: device.id, serialNumberRead: device.serialNumber,
                properties: description?.properties ?? [:],
                reportDescriptor: ProbeReport.hex(description?.reportDescriptor ?? []),
                featureReports: Dictionary(uniqueKeysWithValues: (description?.featureReports ?? []).map { feature in
                    (String(format: "%02X", feature.id), feature.bytes.map(ProbeReport.hex) ?? (feature.error ?? "?"))
                }),
                featureReportsVia: description?.featureReportsVia,
                reports: parsed?.reports.map { String(format: "%@ %02X: %d bytes", $0.kind.rawValue, $0.id, $0.length) } ?? [],
                axisMaximum: parsed?.axisLogicalMaximum, axesDeclaredRelative: parsed?.axesDeclaredRelative,
                buttonUsages: parsed?.buttonUsages ?? [], hasLED: parsed?.hasLED),
            keys: .init(declared: declaredBits.count,
                        found: keys.sorted().map { .init(bit: $0, label: labels[$0] ?? "", catalog: catalogName($0)) },
                        complete: isDone(.keys)),
            axes: .init(fullScale: fullScale,
                        directions: SpaceMouseAxes.Direction.allCases.compactMap { direction in
                            results[direction].map {
                                .init(direction: direction.rawValue, axis: SpaceMouseAxes.axisNames[$0.axis], sign: $0.sign,
                                      peak: $0.peak, asExpected: $0.asExpected)
                            }
                        },
                        range: Dictionary(uniqueKeysWithValues: SpaceMouseAxes.axisNames.enumerated().map { ($1, ranges[$0]) })),
            led: hasLED ? .init(lit: ledLit, wentOut: ledWentOut) : nil,
            label: .init(name: printedName, serialNumber: noSerialPrinted ? "" : printedSerial,
                         noSerialNumberPrinted: noSerialPrinted),
            batteryReports: batteryReports.map(ProbeReport.hex),
            otherInputReports: Dictionary(uniqueKeysWithValues: otherReports.map { (String(format: "%02X", $0.key), ProbeReport.hex($0.value)) }),
            notes: notes)
    }
}

extension SpaceMouseAxes.Direction {
    /// What to do with the cap, in the user's language.
    var localizedInstruction: String {
        switch self {
        case .slideRight: String(localized: "Slide the cap to the right")
        case .slideLeft: String(localized: "Slide the cap to the left")
        case .slideForward: String(localized: "Slide the cap forward, away from you")
        case .slideBack: String(localized: "Slide the cap back, towards you")
        case .push: String(localized: "Push the cap down")
        case .pull: String(localized: "Pull the cap up")
        case .tiltForward: String(localized: "Tilt the cap forward")
        case .tiltBack: String(localized: "Tilt the cap back")
        case .tiltRight: String(localized: "Tilt the cap to the right")
        case .tiltLeft: String(localized: "Tilt the cap to the left")
        case .twistRight: String(localized: "Twist the cap clockwise")
        case .twistLeft: String(localized: "Twist the cap counter-clockwise")
        }
    }
}
