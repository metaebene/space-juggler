import Foundation
import Testing
import SpaceJugglerClient
@testable import SpaceMouseProbe

@MainActor
struct ProbeSessionTests {
    private func session(buttons: Int = 2) -> ProbeSession {
        let session = ProbeSession(device: SpaceMouseDevice(id: "port:1", vendorID: 0x256F, productID: 0xC6FF,
                                                            name: "SpaceMouse Future", transport: "USB", knowledge: .guessed))
        // Axes ±350 in reports 1 and 2, `buttons` buttons in report 3, LED in report 4.
        var descriptor: [UInt8] = [0x05, 0x01, 0x09, 0x08, 0xA1, 0x01,
                                   0x85, 0x01, 0x16, 0xA2, 0xFE, 0x26, 0x5E, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x32,
                                   0x75, 0x10, 0x95, 0x03, 0x81, 0x02,
                                   0x85, 0x02, 0x09, 0x33, 0x09, 0x34, 0x09, 0x35, 0x81, 0x02,
                                   0x85, 0x03, 0x05, 0x09, 0x19, 0x01, 0x29, UInt8(buttons), 0x15, 0x00, 0x25, 0x01,
                                   0x75, 0x01, 0x95, UInt8(buttons), 0x81, 0x02]
        descriptor += [0x85, 0x04, 0x05, 0x08, 0x09, 0x4B, 0x95, 0x01, 0x75, 0x08, 0x91, 0x02, 0xC0]
        session.descriptor = HIDReportDescriptor(descriptor)
        return session
    }

    private func axes(_ values: [Int]) -> [[UInt8]] {
        func le(_ v: Int) -> [UInt8] { let u = UInt16(bitPattern: Int16(v)); return [UInt8(u & 0xFF), UInt8(u >> 8)] }
        return [[0x01] + values[0..<3].flatMap(le), [0x02] + values[3..<6].flatMap(le)]
    }

    @Test func keysAreAskedForOneAfterAnother() {
        let session = session(buttons: 3)
        #expect(session.declaredBits == [0, 1, 2])
        session.ingest([0x03, 0b011])
        session.ingest([0x03, 0b000])
        #expect(session.unlabelled == [0, 1])
        session.label(0, " 1 ")
        session.label(1, "2")
        #expect(!session.isDone(.keys))
        session.ingest([0x03, 0b100])
        session.label(2, "MENU")
        #expect(session.labels == [0: "1", 1: "2", 2: "MENU"])
        #expect(session.isDone(.keys))
    }

    @Test func directionsAreRecordedWhenTheCapIsBack() {
        let session = session()
        #expect(session.asked == .slideRight)
        for report in axes([300, 20, 0, 0, 0, 0]) { session.ingest(report) }
        #expect(session.results.isEmpty)
        for report in axes([0, 0, 0, 0, 0, 0]) { session.ingest(report) }
        #expect(session.results[.slideRight] == .init(axis: 0, sign: 1, peak: 300, asExpected: true))
        #expect(session.asked == .slideLeft)
        // A device whose x runs the other way: recorded as it is, flagged.
        for report in axes([310, 0, 0, 0, 0, 0]) + axes([0, 0, 0, 0, 0, 0]) { session.ingest(report) }
        #expect(session.results[.slideLeft]?.asExpected == false)
        #expect(session.ranges[0] == [0, 310])
    }

    @Test func reportCarriesWhatWasFound() throws {
        let session = session()
        session.ingest([0x17, 0x40, 0x01])
        session.ingest([0x1C, 0x05, 0x00])
        session.ingest([0x03, 0b01])
        session.label(0, "1")
        session.printedName = "SpaceMouse Future"
        let report = session.report(brokerVersion: 4, driverRunning: false)
        #expect(report.batteryReports == ["17 40 01"])
        #expect(report.otherInputReports == ["1C": "1c 05 00"])
        #expect(report.keys.found.first?.label == "1")
        #expect(report.device.productID == "C6FF")
        #expect(report.device.hasLED == true)
        let json = try JSONSerialization.jsonObject(with: report.json) as? [String: Any]
        #expect(json?["format"] as? Int == 1)
    }
}
