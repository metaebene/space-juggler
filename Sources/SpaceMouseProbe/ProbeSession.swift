import Foundation
import Observation
import SpaceJugglerClient

/// Everything the probe has seen and been told about one device, and what is still missing (ADR-0006).
@MainActor
@Observable
final class ProbeSession: Identifiable {
    struct DirectionResult: Equatable {
        var axis: Int
        var sign: Int
        var peak: Int
        var asExpected: Bool
    }

    enum Step: String, CaseIterable, Identifiable {
        case description, keys, axes, led, label
        var id: String { rawValue }
        var title: String {
            switch self {
            case .description: "Description"
            case .keys: "Keys"
            case .axes: "Cap"
            case .led: "LED"
            case .label: "Label"
            }
        }
    }

    let id: String
    var device: SpaceMouseDevice
    var description: DeviceDescription?
    var descriptor: HIDReportDescriptor?

    // Live input
    var axes = SpaceMouseAxes.zero
    var heldBits: Set<Int> = []
    var reportsSeen = 0

    // Keys
    var labels: [Int: String] = [:]
    /// Bits pressed whose label has not been asked yet, oldest first.
    var unlabelled: [Int] = []
    var noMoreKeys = false

    // Axes
    var results: [SpaceMouseAxes.Direction: DirectionResult] = [:]
    var ranges: [[Int]] = Array(repeating: [0, 0], count: 6)
    private var candidate: DirectionResult?

    // LED
    var ledLit: Bool?
    var ledWentOut: Bool?

    // Label
    var printedName = ""
    var printedSerial = ""
    var noSerialPrinted = false
    var notes = ""

    // Other reports
    var batteryReports: [[UInt8]] = []
    var otherReports: [UInt8: [UInt8]] = [:]

    init(device: SpaceMouseDevice) {
        id = device.id
        self.device = device
    }

    // MARK: - What the descriptor says

    var fullScale: Int { descriptor?.axisLogicalMaximum ?? device.axisFullScale ?? SpaceMouseAxes.deviceFullScale }
    /// The buttons the descriptor declares (bit = usage − 1).
    var declaredBits: [Int] { descriptor?.buttonUsages.map { $0 - 1 } ?? [] }
    var hasLED: Bool { descriptor?.hasLED ?? device.hasLED ?? true }
    /// The catalog's name for a bit, if the model is in it.
    func catalogName(_ bit: Int) -> String? {
        SpaceMouseModel.recognise(vendorID: device.vendorID, productID: device.productID, product: device.name,
                                  descriptor: descriptor)?.buttonBits[bit]?.name
    }

    var asked: SpaceMouseAxes.Direction? { SpaceMouseAxes.Direction.allCases.first { results[$0] == nil } }

    // MARK: - Done?

    func isDone(_ step: Step) -> Bool {
        switch step {
        case .description: description?.error == nil && description != nil
        case .keys: (noMoreKeys || !declaredBits.isEmpty && Set(declaredBits).isSubset(of: labels.keys)) && unlabelled.isEmpty
        case .axes: asked == nil
        case .led: !hasLED || (ledLit != nil && ledWentOut != nil)
        case .label: !printedName.isEmpty && (noSerialPrinted || !printedSerial.isEmpty)
        }
    }

    var isComplete: Bool { Step.allCases.allSatisfy(isDone) }

    // MARK: - Input reports

    func ingest(_ bytes: [UInt8]) {
        guard let id = bytes.first else { return }
        reportsSeen += 1
        bytes.withUnsafeBufferPointer { buffer in
            if let bits = SpaceMouseReport.buttonBits(buffer) {
                let now = Set(bits)
                for bit in now.subtracting(heldBits).sorted() where labels[bit] == nil && !unlabelled.contains(bit) {
                    unlabelled.append(bit)
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

    func label(_ bit: Int, _ text: String) {
        labels[bit] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        unlabelled.removeAll { $0 == bit }
    }

    /// Follows the cap through the asked direction: the axis that goes furthest past half the range is what that
    /// direction does; recorded when the cap is back at rest.
    private func axesChanged() {
        let values = axes.all
        for (index, value) in values.enumerated() {
            ranges[index][0] = min(ranges[index][0], value)
            ranges[index][1] = max(ranges[index][1], value)
        }
        guard let asked else { return }
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

    func redoAxes() {
        results = [:]
        candidate = nil
    }

    // MARK: - Report

    func report(brokerVersion: Int?, driverRunning: Bool) -> ProbeReport {
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
                        found: labels.keys.sorted().map { .init(bit: $0, label: labels[$0]!, catalog: catalogName($0)) },
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
            label: .init(name: printedName, serialNumber: printedSerial, noSerialNumberPrinted: noSerialPrinted),
            batteryReports: batteryReports.map(ProbeReport.hex),
            otherInputReports: Dictionary(uniqueKeysWithValues: otherReports.map { (String(format: "%02X", $0.key), ProbeReport.hex($0.value)) }),
            notes: notes)
    }
}
