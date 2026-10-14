import Testing
@testable import SpaceMouseKit

struct SpaceMouseReportTests {
    @Test func translationThenRotationFillsAllAxes() {
        var axes = SpaceMouseAxes.zero
        // x = 350, y = -2, z = 151 (little endian int16), as in stagehand's captures.
        let translation: [UInt8] = [0x01, 0x5E, 0x01, 0xFE, 0xFF, 0x97, 0x00]
        let rotation: [UInt8] = [0x02, 0x00, 0x00, 0x01, 0x00, 0xA2, 0xFE]
        #expect(translation.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(rotation.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(axes == SpaceMouseAxes(x: 350, y: -2, z: 151, rx: 0, ry: 1, rz: -350))
    }

    @Test func buttonReport() {
        let both: [UInt8] = [0x03, 0x03, 0x00]
        #expect(both.withUnsafeBufferPointer { SpaceMouseReport.buttons($0, model: .compact) } == [.left, .right])
        let axisReport: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0]
        #expect(axisReport.withUnsafeBufferPointer { SpaceMouseReport.buttons($0, model: .compact) } == nil)
    }

    /// The SpaceMouse Pro's report 3: the ID and six bytes, keys at 3Dconnexion's bits (stagehand ADR-0087).
    @Test func spaceMouseProKeys() {
        func keys(_ bytes: [UInt8]) -> SpaceMouseButtons? {
            bytes.withUnsafeBufferPointer { SpaceMouseReport.buttons($0, model: .spaceMousePro) }
        }
        #expect(keys([0x03, 0x01, 0, 0, 0, 0, 0]) == .menu)
        #expect(keys([0x03, 0x02, 0, 0, 0, 0, 0]) == .fit)
        #expect(keys([0x03, 0x34, 0, 0, 0, 0, 0]) == [.viewTop, .viewRight, .viewFront])
        #expect(keys([0x03, 0, 0x01, 0, 0, 0, 0]) == .viewRoll)
        #expect(keys([0x03, 0, 0xF0, 0, 0, 0, 0]) == [.key1, .key2, .key3, .key4])
        #expect(keys([0x03, 0, 0, 0x40, 0, 0, 0]) == .escape)
        #expect(keys([0x03, 0, 0, 0x80, 0, 0, 0]) == .alt)
        #expect(keys([0x03, 0, 0, 0, 0x01, 0, 0]) == .shift)
        #expect(keys([0x03, 0, 0, 0, 0x02, 0, 0]) == .control)
        #expect(keys([0x03, 0, 0, 0, 0x04, 0, 0]) == .rotationLock)
        // Bits the Pro has no key for (3Dconnexion's numbering of the bigger models) are no button.
        #expect(keys([0x03, 0xC8, 0x0E, 0x3F, 0xF8, 0xFF, 0xFF]) == [])
        #expect(keys([0x03, 0, 0, 0, 0, 0, 0]) == [])
        // Fifteen keys, each at a bit of its own.
        #expect(Set(SpaceMouseModel.spaceMousePro.buttonBits.values).count == 15)
    }

    /// The SpaceMouse Wireless sends all six axes in one report 1 of twelve bytes (stagehand ADR-0090).
    @Test func singleAxisReportFillsAllAxes() {
        var axes = SpaceMouseAxes.zero
        let report: [UInt8] = [0x01, 0x5E, 0x01, 0xFE, 0xFF, 0x97, 0x00, 0x00, 0x00, 0x01, 0x00, 0xA2, 0xFE]
        #expect(report.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(report.withUnsafeBufferPointer { SpaceMouseReport.completes($0) })
        #expect(axes == SpaceMouseAxes(x: 350, y: -2, z: 151, rx: 0, ry: 1, rz: -350))
    }

    @Test func onlyReport2OrALongReport1Completes() {
        let translation: [UInt8] = [0x01, 0, 0, 0, 0, 0, 0]
        let rotation: [UInt8] = [0x02, 0, 0, 0, 0, 0, 0]
        let buttons: [UInt8] = [0x03, 0x01, 0x00]
        let battery: [UInt8] = [0x17, 0x10, 0x00]
        #expect(!translation.withUnsafeBufferPointer { SpaceMouseReport.completes($0) })
        #expect(rotation.withUnsafeBufferPointer { SpaceMouseReport.completes($0) })
        #expect(!buttons.withUnsafeBufferPointer { SpaceMouseReport.completes($0) })
        var axes = SpaceMouseAxes.zero
        #expect(!battery.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
    }

    @Test func otherReportsAreRejected() {
        var axes = SpaceMouseAxes.zero
        let led: [UInt8] = [0x04, 0x01, 0, 0, 0, 0, 0]
        #expect(!led.withUnsafeBufferPointer { SpaceMouseReport.take($0, into: &axes) })
        #expect(axes == .zero)
    }
}

struct SpaceMouseReportExtrasTests {
    private func battery(_ bytes: [UInt8]) -> (percent: Int, charging: Bool)? {
        bytes.withUnsafeBufferPointer { SpaceMouseReport.battery($0) }
    }

    @Test func batteryReport() {
        let captured = battery([0x17, 0x10, 0x00]) // captured at the device (stagehand)
        #expect(captured?.percent == 16 && captured?.charging == false)
        let charging = battery([0x17, 100, 0x01])
        #expect(charging?.percent == 100 && charging?.charging == true)
        #expect(battery([0x17, 101, 0x00]) == nil)
        #expect(battery([0x03, 50, 0x00]) == nil)
        #expect(battery([0x17]) == nil)
        // Not a button report either.
        #expect([UInt8]([0x17, 0x03, 0x00]).withUnsafeBufferPointer { SpaceMouseReport.buttons($0, model: .compact) } == nil)
    }

    /// As read at the device over both transports; the label says "S/N:Z5024520019" (stagehand ADR-0092).
    @Test func serialNumberReport() {
        #expect(SpaceMouseReport.serialNumber([0x08, 0x5A, 0x00, 0x01, 0x2B, 0x7C, 0x17, 0x53]) == "Z5024520019")
        #expect(SpaceMouseReport.serialNumber([0x08, 0x5A, 0, 0, 0, 0, 0, 0]) == nil)
        #expect(SpaceMouseReport.serialNumber([0x08, 0x00, 0x00, 0x01, 0x2B, 0x7C, 0x17, 0x53]) == nil)
        #expect(SpaceMouseReport.serialNumber([0x09, 0x5A, 0x00, 0x01, 0x2B, 0x7C, 0x17, 0x53]) == nil)
        #expect(SpaceMouseReport.serialNumber([0x08, 0x5A]) == nil)
        #expect(SpaceMouseModel.spaceMouseWireless.serialFeatureReportID == 0x08)
        #expect(SpaceMouseModel.compact.serialFeatureReportID == nil)
    }

    @Test func unknownBits() {
        func unknown(_ bytes: [UInt8], _ model: SpaceMouseModel) -> Int? {
            bytes.withUnsafeBufferPointer { SpaceMouseReport.unknownBit($0, model: model) }
        }
        #expect(unknown([0x03, 0x08, 0x00, 0x00, 0x00], .spaceMousePro) == 3)
        #expect(unknown([0x03, 0x01, 0x00, 0x00, 0x00], .spaceMousePro) == nil)
        #expect(unknown([0x03, 0x04, 0x00], .compact) == 2)
        #expect(unknown([0x01, 0xFF, 0xFF], .compact) == nil)
    }

    @Test func twoButtonsAndLED() {
        let compact = SpaceMouseModel.compact.twoButtons, pro = SpaceMouseModel.spaceMousePro.twoButtons
        #expect(compact.left == .left && compact.right == .right)
        #expect(pro.left == .menu && pro.right == .fit)
        #expect(SpaceMouseModel.spaceMousePro.asTwoButtons([.menu, .key1]) == .left)
        #expect(SpaceMouseModel.compact.asTwoButtons([.left, .right]) == [.left, .right])
        #expect(SpaceMouseModel.known.allSatisfy { $0.hasStatusLED })
        #expect(SpaceMouseModel.known.filter(\.statusLEDNeedsCable) == [.spaceMouseWireless])
    }
}

struct SpaceMouseModelTests {
    @Test func modelsAreMatchedByVendorAndProductTogether() {
        #expect(SpaceMouseModel.matching(vendorID: 0x256F, productID: 0xC635) == .compact)
        #expect(SpaceMouseModel.matching(vendorID: 0x046D, productID: 0xC626) == .spaceNavigator)
        #expect(SpaceMouseModel.matching(vendorID: 0x046D, productID: 0xC62B) == .spaceMousePro)
        #expect(SpaceMouseModel.matching(vendorID: 0x256F, productID: 0xC63A) == .spaceMouseWireless)
        // The SpaceMouse Pro Wireless and the Universal Receiver are other devices.
        #expect(SpaceMouseModel.matching(vendorID: 0x256F, productID: 0xC631) == nil)
        #expect(SpaceMouseModel.matching(vendorID: 0x256F, productID: 0xC652) == nil)
        // Another Logitech device is no SpaceMouse (ADR-0003).
        #expect(SpaceMouseModel.matching(vendorID: 0x046D, productID: 0xC635) == nil)
    }

    @Test func driverProductIDsNameTheModel() {
        #expect(SpaceMouseModel.matching(productID: 0xC62B) == .spaceMousePro)
        #expect(SpaceMouseModel.matching(productID: 0xC63A) == .spaceMouseWireless)
        #expect(Set(SpaceMouseModel.known.map(\.productID)).count == SpaceMouseModel.known.count)
    }

    @Test func twoButtonModelsShareTheirBits() {
        for model in [SpaceMouseModel.compact, .spaceNavigator, .spaceMouseWireless] {
            #expect(model.buttons(0x01) == .left)
            #expect(model.buttons(0x03) == [.left, .right])
            #expect(model.buttons(0x04) == [])
        }
    }
}

struct ConnexionDeviceStateTests {
    /// Builds a 48-byte `ConnexionDeviceState` (pack 2) the way the driver sends it.
    private func state(client: UInt16, command: UInt16, axes: [Int16], buttons: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 48)
        func put16(_ value: UInt16, at offset: Int) {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8(value >> 8)
        }
        put16(0x6D33, at: 0)
        put16(client, at: 2)
        put16(command, at: 4)
        for (index, value) in axes.enumerated() { put16(UInt16(bitPattern: value), at: 30 + 2 * index) }
        put16(UInt16(buttons & 0xFFFF), at: 44)
        put16(UInt16(buttons >> 16), at: 46)
        return bytes
    }

    @Test func decodesAxisState() throws {
        let bytes = state(client: 4098, command: 3, axes: [-260, 522, 0, 1, -1, 100], buttons: 0)
        let decoded = try #require(bytes.withUnsafeBytes { ConnexionDeviceState($0) })
        #expect(decoded.client == 4098)
        #expect(decoded.command == ConnexionDeviceState.handleAxis)
        #expect(decoded.axes == SpaceMouseAxes(x: -260, y: 522, z: 0, rx: 1, ry: -1, rz: 100))
    }

    @Test func decodesButtonState() throws {
        let bytes = state(client: 1, command: 2, axes: [0, 0, 0, 0, 0, 0], buttons: 0x3)
        let decoded = try #require(bytes.withUnsafeBytes { ConnexionDeviceState($0) })
        #expect(decoded.command == ConnexionDeviceState.handleButtons)
        #expect(decoded.buttonBits == 0x3)
        #expect(SpaceMouseModel.compact.buttons(UInt64(decoded.buttonBits)) == [.left, .right])
    }

    @Test func rejectsShortBuffers() {
        let bytes = [UInt8](repeating: 0, count: 47)
        #expect(bytes.withUnsafeBytes { ConnexionDeviceState($0) } == nil)
    }
}
