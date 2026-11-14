import Foundation
import Testing
@testable import SpaceJugglerCore
import SpaceMouseKit

/// The report buffer of an open device: what one input report becomes (`Devices` without IOKit).
@MainActor
struct ReportsTests {
    final class Seen {
        var raw: [[UInt8]] = []
        var axes: [SpaceMouseAxes] = []
        var buttons: [SpaceMouseButtons] = []
        var battery: [(Int, Bool)] = []
    }

    private func reports(_ model: SpaceMouseModel = .compact) -> (Reports, Seen) {
        let seen = Seen()
        let reports = Reports(model: model,
                              onReport: { seen.raw.append(Array($0)) },
                              onAxes: { seen.axes.append($0) },
                              onButtons: { seen.buttons.append($0) },
                              onBattery: { seen.battery.append(($0, $1)) })
        return (reports, seen)
    }

    private func ingest(_ reports: Reports, _ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { reports.ingest($0) }
    }

    @Test func buttonsAreReportedOnChangeOnly() {
        let (reports, seen) = reports()
        ingest(reports, [3, 0b01, 0])
        ingest(reports, [3, 0b01, 0])
        ingest(reports, [3, 0b11, 0])
        ingest(reports, [3, 0b00, 0])
        #expect(seen.buttons == [[.left], [.left, .right], []])
        #expect(seen.raw.count == 4, "every report as it came")
        #expect(seen.axes.isEmpty)
    }

    @Test func aPairOfAxisReportsMakesOnePicture() {
        let (reports, seen) = reports()
        ingest(reports, [1, 0x2C, 0x01, 0x00, 0x00, 0xFF, 0xFF])        // x 300, y 0, z -1
        #expect(seen.axes.isEmpty, "report 1 alone is half a picture")
        ingest(reports, [2, 0x00, 0x00, 0x0A, 0x00, 0xF6, 0xFF])        // rx 0, ry 10, rz -10
        #expect(seen.axes == [SpaceMouseAxes(x: 300, y: 0, z: -1, rx: 0, ry: 10, rz: -10)])
    }

    @Test func oneLongReportStandsAlone() {
        let (reports, seen) = reports(.spaceMouseWireless)
        ingest(reports, [1, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05, 0x00, 0x06, 0x00])
        #expect(seen.axes == [SpaceMouseAxes(x: 1, y: 2, z: 3, rx: 4, ry: 5, rz: 6)])
    }

    @Test func aCapRestingOffItsCentreIsPassedOnAsAtRest() {
        // ADR-0010: what goes on is the deflection from where the cap rests.
        let seen = Seen()
        var now = 0.0
        var rests: [SpaceMouseAxes] = []
        let reports = Reports(model: .spaceNavigator, onReport: { _ in }, onAxes: { seen.axes.append($0) },
                              onButtons: { _ in }, onBattery: { _, _ in }, onRest: { rests.append($0) }, clock: { now })
        for _ in 0..<120 {
            ingest(reports, [1, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00])        // y 32
            ingest(reports, [2, 0x00, 0x00, 0x00, 0x00, 0xE2, 0xFF])        // rz -30
            now += 0.016
        }
        #expect(seen.axes.first == SpaceMouseAxes(y: 32, rz: -30))
        #expect(seen.axes.last == .zero)
        #expect(rests == [SpaceMouseAxes(y: 32, rz: -30)])
    }

    @Test func aDeviceOpenedWhileTheCapIsTiltedIsSeizableOnlyOnceItIsBack() {
        // ADR-0017: opened without seizing, the holder steers at once; seizable once macOS has seen the zeros.
        let seen = Seen()
        var now = 100.0
        var found = 0
        let reports = Reports(model: .spaceNavigator, onReport: { _ in }, onAxes: { seen.axes.append($0) },
                              onButtons: { seen.buttons.append($0) }, onBattery: { _, _ in }, clock: { now })
        reports.onSeizable = { found += 1 }
        reports.awaitRest()
        #expect(reports.awaitingRest)
        for _ in 0..<200 {
            ingest(reports, [1, 0x00, 0x00, 0xC4, 0xFF, 0x00, 0x00])        // y -60
            ingest(reports, [2, 0xC4, 0xFF, 0x00, 0x00, 0x00, 0x00])        // rx -60
            now += 0.016
        }
        #expect(seen.axes.count == 200 && seen.axes.allSatisfy { $0 == SpaceMouseAxes(y: -60, rx: -60) })
        #expect(found == 0 && reports.seizable == nil)
        #expect(reports.untilNextCheck.map { $0 > 0 && $0 <= SeizeGate.quiet } == true)
        ingest(reports, [1, 0, 0, 0, 0, 0, 0])
        ingest(reports, [2, 0, 0, 0, 0, 0, 0])
        #expect(seen.axes.last == .zero)
        #expect(reports.seizable == nil, "macOS may still be taking the zeros")
        now += SeizeGate.quiet
        #expect(reports.seizable == .quiet)
        #expect(found == 0, "a look without a report finds a quiet cap, no report does")
        reports.seized()
        #expect(!reports.awaitingRest && reports.seizable == nil && reports.untilNextCheck == nil)
        // Seized, the same reports go on: a button pressed after the reopen is one change, not a repeat.
        ingest(reports, [3, 0b01, 0])
        ingest(reports, [3, 0b00, 0])
        #expect(seen.buttons == [[.left], []])
        #expect(found == 0)
    }

    @Test func aWornCapIsSeizableFromItsOwnReports() {
        var now = 0.0
        var foundAt: [Double] = []
        let reports = Reports(model: .spaceNavigator, onReport: { _ in }, onAxes: { _ in }, onButtons: { _ in },
                              onBattery: { _, _ in }, clock: { now })
        reports.onSeizable = { foundAt.append(now) }
        reports.awaitRest()
        for _ in 0..<120 {
            ingest(reports, [1, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00])        // y 32
            ingest(reports, [2, 0x00, 0x00, 0x00, 0x00, 0xE2, 0xFF])        // rz -30
            if !foundAt.isEmpty { break }
            now += 0.016
        }
        #expect(foundAt.count == 1 && foundAt[0] >= CapRest.settle && foundAt[0] < CapRest.settle + 0.02)
        #expect(reports.seizable == .rested)
        // A hand on the cap before the seize came round: not any more.
        ingest(reports, [1, 0x00, 0x00, 0x20, 0x01, 0x00, 0x00])        // y 288
        ingest(reports, [2, 0x00, 0x00, 0x00, 0x00, 0xE2, 0xFF])
        #expect(reports.seizable == nil)
    }

    @Test func notWatchingNothingIsSeizable() {
        let (reports, _) = reports()
        ingest(reports, [3, 0b01, 0])
        #expect(!reports.awaitingRest && reports.seizable == nil && reports.untilNextCheck == nil)
    }

    @Test func batteryAndUnknownReports() {
        let (reports, seen) = reports(.spaceMouseWireless)
        ingest(reports, [0x17, 80, 1])
        ingest(reports, [0x1C, 5, 0])
        #expect(seen.battery.map(\.0) == [80])
        #expect(seen.battery.map(\.1) == [true])
        #expect(seen.raw.count == 2)
        #expect(seen.axes.isEmpty && seen.buttons.isEmpty)
    }
}
