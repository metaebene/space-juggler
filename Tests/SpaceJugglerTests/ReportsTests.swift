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
        let reports = Reports(size: 64, model: model,
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
