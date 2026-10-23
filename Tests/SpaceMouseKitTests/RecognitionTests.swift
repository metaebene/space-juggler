import Foundation
import Testing
@testable import SpaceMouseKit

/// The SpaceMouse Compact's report descriptor as the IORegistry shows it (`ReportDescriptor`, 2026-10-15).
let compactDescriptor: [UInt8] = hex("""
    05010908a101a100850116a2fe265e013688fa467805550c6511093009310932751095038106c0a1008502093309340935751095038106c0\
    a102850305010509190129021500250135004501750195028102950e8103c0a10285040508094b15002501950175019102950175079103c0\
    0600ff0901a1021580257f7508093aa102850509209501b102c0a102850609219501b102c0a102850709229501b102c0a102850809239507\
    b102c0a102850909249507b102c0a102850a09259507b102c0a102850b09269501b102c0a1028513092e9501b102c0a102851909319504b1\
    02c0a102851a09329507b102c0c0c0
    """)

/// The SpaceTraveler's report descriptor (046D:C623, fw 0x0311), from the Space Probe report in issue #1 (2026-10-16).
let travelerDescriptor: [UInt8] = hex("""
    05010908a101a1008501160cfe26f40136008046ff7f093009310932751095038106c0a1008502093309340935751095038106c0a1028503\
    0501050919012908150025013500450175019508810295088103c0a10285040508194b294c15002501950275019102950175069103c00600\
    ff0901a1021580257f7508093aa102850509209501b102c0a102850609219501b102c0a102850709229501b102c0a102850809239507b102\
    c0a102850909249507b102c0a102850a09259507b102c0a102850b09269501b102c0c0c0
    """)

func hex(_ text: String) -> [UInt8] {
    let digits = text.filter(\.isHexDigit)
    return stride(from: 0, to: digits.count - 1, by: 2).map { offset in
        let start = digits.index(digits.startIndex, offsetBy: offset)
        return UInt8(digits[start...digits.index(after: start)], radix: 16)!
    }
}

struct HIDReportDescriptorTests {
    @Test func compactReports() throws {
        let descriptor = try #require(HIDReportDescriptor(compactDescriptor))
        #expect(descriptor.isMultiAxisController)
        #expect(descriptor.report(1, .input)?.length == 7)
        #expect(descriptor.report(2, .input)?.length == 7)
        #expect(descriptor.report(3, .input)?.length == 3)
        #expect(descriptor.report(4, .output)?.length == 2)
        #expect(descriptor.axisLogicalMaximum == 350)
        #expect(descriptor.axesDeclaredRelative)
        #expect(descriptor.buttonUsages == [1, 2])
        #expect(descriptor.hasLED)
        #expect(descriptor.featureReportIDs == [0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x13, 0x19, 0x1A])
        #expect(descriptor.report(0x08, .feature)?.length == 8)
        #expect(descriptor.report(0x19, .feature)?.length == 5)
    }

    @Test func travelerReports() throws {
        let descriptor = try #require(HIDReportDescriptor(travelerDescriptor))
        #expect(descriptor.isMultiAxisController)
        #expect(descriptor.report(1, .input)?.length == 7)
        #expect(descriptor.report(2, .input)?.length == 7)
        #expect(descriptor.report(3, .input)?.length == 3)
        #expect(descriptor.report(4, .output)?.length == 2)
        #expect(descriptor.axisLogicalMaximum == 500)
        #expect(descriptor.axesDeclaredRelative)
        #expect(descriptor.buttonUsages == Array(1...8))
        #expect(descriptor.hasLED)
        #expect(descriptor.featureReportIDs == [0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B])
    }

    @Test func truncatedDescriptorIsRejected() {
        #expect(HIDReportDescriptor([0x05, 0x01, 0x09]) == nil)
        #expect(HIDReportDescriptor([]) != nil)
    }

    @Test func unsignedLogicalMaximum() throws {
        // Usage Page Button, Logical 0 … 255 written as one byte (0xFF), 8 bits, input.
        let descriptor = try #require(HIDReportDescriptor([0x05, 0x09, 0x09, 0x01, 0x15, 0x00, 0x25, 0xFF, 0x75, 0x08,
                                                            0x95, 0x01, 0x81, 0x02]))
        #expect(descriptor.reports.first?.fields.first?.logicalMaximum == 255)
    }

    @Test func repeatedUsagesAreOneButtonEach() throws {
        // Button page, Usage Minimum 1, Usage Maximum 2, but four bits: elements beyond the last usage repeat it
        // (HID 6.2.2.8), so there are two buttons, not four.
        let descriptor = try #require(HIDReportDescriptor([0x05, 0x09, 0x19, 0x01, 0x29, 0x02, 0x15, 0x00, 0x25, 0x01,
                                                            0x75, 0x01, 0x95, 0x04, 0x81, 0x02]))
        #expect(descriptor.buttonUsages == [1, 2])
    }
}

struct RecognitionTests {
    private let compact = HIDReportDescriptor(compactDescriptor)

    @Test func catalogModelsKeepTheirKeysAndTakeTheDescriptorsRange() throws {
        let model = try #require(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC635, product: "SpaceMouse Compact",
                                                           descriptor: compact))
        #expect(model == .compact)
        #expect(model.knowledge == .checked)
        #expect(model.axisFullScale == 350)
        #expect(model.hasStatusLED)
        // A SpaceNavigator whose descriptor says ±350 (public dumps) gets 350, without a descriptor the catalog's 500.
        let navigator = try #require(SpaceMouseModel.recognise(vendorID: 0x046D, productID: 0xC626, product: nil,
                                                               descriptor: compact))
        #expect(navigator.axisFullScale == 350)
        #expect(SpaceMouseModel.recognise(vendorID: 0x046D, productID: 0xC626, product: nil, descriptor: nil)?.axisFullScale == 500)
    }

    @Test func theSpaceTravelerIsInTheCatalog() throws {
        let model = try #require(SpaceMouseModel.recognise(vendorID: 0x046D, productID: 0xC623, product: "SpaceTraveler USB",
                                                           descriptor: HIDReportDescriptor(travelerDescriptor)))
        #expect(model == .spaceTraveler)
        #expect(model.knowledge == .checked)
        #expect(model.axisFullScale == 500)
        #expect(model.hasStatusLED)
        #expect(model.buttons(0xFF) == [.key1, .key2, .key3, .key4, .key5, .key6, .key7, .key8])
        #expect(model.serialFeatureReportID == nil)
    }

    @Test func anUnknownMultiAxisControllerIsGuessed() throws {
        let model = try #require(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC6FF, product: "SpaceMouse Future",
                                                           descriptor: compact))
        #expect(model.knowledge == .guessed)
        #expect(model.name == "SpaceMouse Future")
        #expect(model.buttons == [.left, .right])
        #expect(model.axisFullScale == 350)
        #expect(model.serialFeatureReportID == 0x08)
    }

    @Test func universalReceiverSlotsAreNamedByTheirButtons() throws {
        let model = try #require(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC652, product: "3Dconnexion Universal Receiver",
                                                           descriptor: compact))
        #expect(model.name == "SpaceMouse Wireless (Universal Receiver)")
        #expect(model.knowledge == .published)
        #expect(model.serialFeatureReportID == nil)
    }

    @Test func otherDevicesAreNot() {
        // A CadMouse, another vendor, a device without a Multi-axis Controller, an unknown one without descriptor.
        #expect(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC650, product: "CadMouse", descriptor: compact) == nil)
        #expect(SpaceMouseModel.recognise(vendorID: 0x05AC, productID: 0xC635, product: nil, descriptor: compact) == nil)
        #expect(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC6FF, product: nil,
                                          descriptor: HIDReportDescriptor([0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0xC0])) == nil)
        #expect(SpaceMouseModel.recognise(vendorID: 0x256F, productID: 0xC6FF, product: nil, descriptor: nil) == nil)
    }

    @Test func sharedNumbering() {
        // The Pro's checked keys are the shared numbering's at the same bits.
        for (bit, button) in SpaceMouseModel.spaceMousePro.buttonBits {
            #expect(SpaceMouseModel.sharedNumbering[bit] == button)
        }
        #expect(SpaceMouseModel.enterprise.buttons(bits: [174, 175, 76]) == [.tab, .space, .key11])
        #expect(Set(SpaceMouseModel.enterprise.buttonBits.values).count == 31)
        #expect(Set(SpaceMouseModel.spacePilotPro.buttonBits.values).count == 31)
        #expect(Set(SpaceMouseModel.spaceExplorer.buttonBits.values).count == 15)
        #expect(Set(SpaceMouseModel.spacePilot.buttonBits.values).count == 21)
        // Every model's buttons are distinct and named.
        for model in SpaceMouseModel.known {
            #expect(Set(model.buttonBits.values).count == model.buttonBits.count, "\(model.name)")
            #expect(!model.buttons.name.isEmpty)
        }
    }

    @Test func enterpriseKeysBeyondSixtyFourBits() {
        var report = [UInt8](repeating: 0, count: 23)
        report[0] = 3
        report[1 + 175 / 8] |= 1 << (175 % 8)
        report[1 + 12 / 8] |= 1 << (12 % 8)
        #expect(report.withUnsafeBufferPointer { SpaceMouseReport.buttons($0, model: .enterprise) } == [.space, .key1])
    }

    @Test func buttonNames() {
        #expect(SpaceMouseButtons.viewRollReverse.name == "Roll back")
        #expect(SpaceMouseButtons([.escape, .key1]).name == "1 + ESC")
        #expect(SpaceMouseButtons.allCases.count == 43)
    }

    @Test func directions() {
        let axes = SpaceMouseAxes(x: 200, y: -50, rz: -400)
        #expect(axes.along(.slideRight) == 200)
        #expect(axes.along(.slideLeft) == 0)
        #expect(axes.along(.slideForward) == 50)
        #expect(axes.strongest == .twistLeft)
        #expect(axes.fraction(.twistLeft, fullScale: 500) == 0.8)
        #expect(axes.fraction(.twistLeft) == 1)
    }
}
