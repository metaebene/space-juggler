import Foundation

/// Deflection of the SpaceMouse cap, as the input reports it. Native HID: raw device units, about ±350 per axis.
/// Axis signs, seen from the user with the cable at the back (stagehand, docs/spacemouse-findings.md):
/// slide right x+, slide forward y−, push down z+, tilt forward rx−, tilt right ry−,
/// twist clockwise seen from above rz+.
public struct SpaceMouseAxes: Sendable, Equatable, Codable, CustomStringConvertible {
    public var x = 0, y = 0, z = 0
    public var rx = 0, ry = 0, rz = 0

    public init(x: Int = 0, y: Int = 0, z: Int = 0, rx: Int = 0, ry: Int = 0, rz: Int = 0) {
        self.x = x; self.y = y; self.z = z
        self.rx = rx; self.ry = ry; self.rz = rz
    }

    public static let zero = SpaceMouseAxes()
    /// Logical maximum of every axis in the HID report descriptor of the SpaceMouse Compact, Pro and Wireless.
    public static let deviceFullScale = 350

    public var all: [Int] { [x, y, z, rx, ry, rz] }
    public var isZero: Bool { self == .zero }

    public var description: String { "x \(x) y \(y) z \(z) rx \(rx) ry \(ry) rz \(rz)" }
}

/// The buttons held, by what they are, whichever model has them: each model says which bit of its button report is
/// which (`SpaceMouseModel.buttonBits`).
public struct SpaceMouseButtons: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    /// The two buttons of the SpaceMouse Compact, the SpaceNavigator and the SpaceMouse Wireless: 1 (left), 2 (right).
    public static let left = SpaceMouseButtons(rawValue: 1 << 0)
    public static let right = SpaceMouseButtons(rawValue: 1 << 1)
    /// The fifteen keys of the SpaceMouse Pro, named as printed (stagehand ADR-0087). Its 1 and 2 are keys of their
    /// own, not the Compact's two.
    public static let key1 = SpaceMouseButtons(rawValue: 1 << 2)
    public static let key2 = SpaceMouseButtons(rawValue: 1 << 3)
    public static let key3 = SpaceMouseButtons(rawValue: 1 << 4)
    public static let key4 = SpaceMouseButtons(rawValue: 1 << 5)
    public static let menu = SpaceMouseButtons(rawValue: 1 << 6)
    public static let fit = SpaceMouseButtons(rawValue: 1 << 7)
    /// The view keys T, R, F and the one with the turning square (roll view).
    public static let viewTop = SpaceMouseButtons(rawValue: 1 << 8)
    public static let viewRight = SpaceMouseButtons(rawValue: 1 << 9)
    public static let viewFront = SpaceMouseButtons(rawValue: 1 << 10)
    public static let viewRoll = SpaceMouseButtons(rawValue: 1 << 11)
    public static let escape = SpaceMouseButtons(rawValue: 1 << 12)
    public static let shift = SpaceMouseButtons(rawValue: 1 << 13)
    public static let control = SpaceMouseButtons(rawValue: 1 << 14)
    public static let alt = SpaceMouseButtons(rawValue: 1 << 15)
    public static let rotationLock = SpaceMouseButtons(rawValue: 1 << 16)
}

/// A device the native input reads, matched by vendor **and** product ID (ADR-0003). All of them send their axes in
/// reports 1 and 2 or in one long report 1, their buttons in report 3, and take output report 4 for the LED (ADR-0023,
/// Kugelblitz ADR-0134).
public struct SpaceMouseModel: Sendable, Equatable {
    public let vendorID: Int
    public let productID: Int
    public let name: String
    /// Which bit of the button report (bit 0 = the lowest bit of the byte after the report ID) is which button.
    public let buttonBits: [Int: SpaceMouseButtons]

    public static let compact = SpaceMouseModel(vendorID: 0x256F, productID: 0xC635, name: "SpaceMouse Compact",
                                                buttonBits: twoButtons)
    /// From the Logitech years, hence Logitech's vendor ID. Report descriptor read from the IORegistry (2026-10-04):
    /// the Compact's reports, but a logical range of ±500 instead of ±350.
    public static let spaceNavigator = SpaceMouseModel(vendorID: 0x046D, productID: 0xC626, name: "SpaceNavigator",
                                                       buttonBits: twoButtons)
    /// Also from the Logitech years. The Compact's axes (±350) and LED; fifteen keys in a report 3 of six bytes, at
    /// 3Dconnexion's numbering shared with the bigger models, hence the gaps (stagehand ADR-0087: descriptor and every
    /// key checked at a device, 2026-10-05).
    public static let spaceMousePro = SpaceMouseModel(
        vendorID: 0x046D, productID: 0xC62B, name: "SpaceMouse Pro",
        buttonBits: [0: .menu, 1: .fit, 2: .viewTop, 4: .viewRight, 5: .viewFront, 8: .viewRoll,
                     12: .key1, 13: .key2, 14: .key3, 15: .key4,
                     22: .escape, 23: .alt, 24: .shift, 25: .control, 26: .rotationLock])
    /// The Bluetooth Edition, over Bluetooth and on its USB cable with the same IDs and descriptor: the Compact's two
    /// buttons, all six axes (±350) in one report 1 of twelve bytes (stagehand ADR-0090, ADR-0091). Over the Universal
    /// Receiver it is another device, not known here.
    public static let spaceMouseWireless = SpaceMouseModel(vendorID: 0x256F, productID: 0xC63A,
                                                           name: "SpaceMouse Wireless", buttonBits: twoButtons)
    public static let known: [SpaceMouseModel] = [.compact, .spaceNavigator, .spaceMousePro, .spaceMouseWireless]

    private static let twoButtons: [Int: SpaceMouseButtons] = [0: .left, 1: .right]

    /// Every model has one status LED, switched with output report 4 (`04 01` / `04 00`); the device does not report
    /// its state, so whoever writes it mirrors it (stagehand ADR-0083).
    public var hasStatusLED: Bool { true }

    /// The SpaceMouse Wireless takes output report 4 over Bluetooth, but its LED lights only on the USB cable
    /// (stagehand ADR-0091, seen at the device).
    public var statusLEDNeedsCable: Bool { self == .spaceMouseWireless }

    /// The vendor feature report that carries the serial number, for the models whose HID device has none on any
    /// transport: the Wireless (printed on its label, stagehand ADR-0092) and the Compact (different on two devices,
    /// taken as its serial number, docs/serial-report.md). The SpaceNavigator and the SpaceMouse Pro declare it too, but
    /// leave it empty. The only feature report ever read, and only with GET.
    public var serialFeatureReportID: UInt8? {
        self == .spaceMouseWireless || self == .compact ? SpaceMouseReport.serialReportID : nil
    }

    /// The two buttons a program uses that only knows two: the Compact's left and right, the Pro's MENU and FIT
    /// (Space Glider ADR-0025).
    public var twoButtons: (left: SpaceMouseButtons, right: SpaceMouseButtons) {
        self == .spaceMousePro ? (.menu, .fit) : (.left, .right)
    }

    /// `held` as a program sees it that only knows two buttons: `.left` and `.right` (`twoButtons`).
    public func asTwoButtons(_ held: SpaceMouseButtons) -> SpaceMouseButtons {
        var two: SpaceMouseButtons = []
        if held.contains(twoButtons.left) { two.insert(.left) }
        if held.contains(twoButtons.right) { two.insert(.right) }
        return two
    }

    public static func matching(vendorID: Int, productID: Int) -> SpaceMouseModel? {
        known.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// The model behind a product ID the 3DxWare driver names (it gives no vendor ID); the known models' product IDs
    /// differ.
    public static func matching(productID: Int) -> SpaceMouseModel? {
        known.first { $0.productID == productID }
    }

    /// The buttons held according to a bitmap in the device's numbering (report 3, or the driver's state).
    public func buttons(_ bitmap: UInt64) -> SpaceMouseButtons {
        buttonBits.reduce(into: []) { held, entry in
            if (0..<64).contains(entry.key), bitmap & 1 << UInt64(entry.key) != 0 { held.insert(entry.value) }
        }
    }
}

/// Decodes the input reports of the models in `SpaceMouseModel.known`. From Kugelblitz's copy (itself ported from
/// stagehand's `SpaceMouseReport` via Spacer), with stagehand's battery, serial number and unknown bits. The report buffer includes the report ID as byte 0.
public enum SpaceMouseReport {
    public static let translationReportID: UInt8 = 1
    public static let rotationReportID: UInt8 = 2
    public static let buttonReportID: UInt8 = 3
    /// The SpaceMouse Wireless's battery (`17 <percent> <flags>`, stagehand ADR-0090).
    public static let batteryReportID: UInt8 = 0x17
    /// Vendor feature report with the serial number of the SpaceMouse Wireless and the Compact (`serialFeatureReportID`).
    public static let serialReportID: UInt8 = 0x08

    /// The bitmap of report 3 in the device's numbering (its first 64 bits); nil for other reports.
    public static func buttonBitmap(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt64? {
        guard bytes.count >= 2, bytes[0] == buttonReportID else { return nil }
        return bytes.dropFirst().prefix(8).enumerated().reduce(0) { $0 | UInt64($1.element) << UInt64(8 * $1.offset) }
    }

    /// Buttons held according to report 3, with the model's bits; nil for other reports.
    public static func buttons(_ bytes: UnsafeBufferPointer<UInt8>, model: SpaceMouseModel) -> SpaceMouseButtons? {
        buttonBitmap(bytes).map(model.buttons)
    }

    /// The lowest bit set in report 3 that stands for no button of `model`: a key the catalog does not know yet, for a
    /// diagnostic. Nil when there is none, and for other reports.
    public static func unknownBit(_ bytes: UnsafeBufferPointer<UInt8>, model: SpaceMouseModel) -> Int? {
        guard bytes.count >= 2, bytes[0] == buttonReportID else { return nil }
        return (0..<(bytes.count - 1) * 8).first { bit in
            bytes[1 + bit / 8] & UInt8(1 << (bit % 8)) != 0 && model.buttonBits[bit] == nil
        }
    }

    /// The battery of report 0x17: the level 0 … 100 (Battery Strength) and the lowest flag bit, a vendor usage that
    /// presumably means "charging" (stagehand ADR-0090, not yet seen set at the device). Nil for other reports and for
    /// a level out of range.
    public static func battery(_ bytes: UnsafeBufferPointer<UInt8>) -> (percent: Int, charging: Bool)? {
        guard bytes.count >= 2, bytes[0] == batteryReportID, bytes[1] <= 100 else { return nil }
        return (Int(bytes[1]), bytes.count >= 3 && bytes[2] & 1 != 0)
    }

    /// The serial number from the serial feature report as IOKit hands it over: a letter, then six bytes as one
    /// big-endian number in decimal (Wireless `08 5a 00 01 2b 7c 17 53` = "Z5024520019" as on its label, stagehand
    /// ADR-0092); when the second byte is a letter too, two letters and five bytes (a Compact's `08 53 53 01 01 62 5f ac`
    /// = "SS4318191532", docs/serial-report.md). Nil for anything else and for an all-zero number.
    public static func serialNumber(_ bytes: [UInt8]) -> String? {
        func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        guard bytes.count >= 8, bytes[0] == serialReportID, isLetter(bytes[1]) else { return nil }
        let letters = isLetter(bytes[2]) ? 2 : 1
        let number = bytes[(1 + letters)...7].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard number > 0 else { return nil }
        return String(decoding: bytes[1...letters], as: UTF8.self) + "\(number)"
    }

    /// Report 1 sets x y z (all six when it carries twelve bytes, as on the SpaceMouse Wireless), report 2 sets
    /// rx ry rz, each as int16 little endian. Returns false for any other report.
    public static func take(_ bytes: UnsafeBufferPointer<UInt8>, into axes: inout SpaceMouseAxes) -> Bool {
        guard bytes.count >= 7,
              bytes[0] == translationReportID || bytes[0] == rotationReportID else { return false }
        func value(_ at: Int) -> Int {
            Int(Int16(bitPattern: UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8))
        }
        if bytes[0] == translationReportID {
            axes.x = value(1); axes.y = value(3); axes.z = value(5)
            if bytes.count >= 13 { axes.rx = value(7); axes.ry = value(9); axes.rz = value(11) }
        } else {
            axes.rx = value(1); axes.ry = value(3); axes.rz = value(5)
        }
        return true
    }

    /// Whether an axis report finishes a full picture of the cap: report 2 ends a pair, a report 1 with all six axes
    /// stands alone.
    public static func completes(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let id = bytes.first else { return false }
        return id == rotationReportID || id == translationReportID && bytes.count >= 13
    }
}

/// `ConnexionDeviceState` of the 3DxWare client API (ConnexionClient.h, `#pragma pack(2)`, 48 bytes), as delivered
/// with the message `kConnexionMsgDeviceState` ('3dSR').
public struct ConnexionDeviceState: Sendable, Equatable {
    public static let size = 48
    public static let handleButtons = 2
    public static let handleAxis = 3

    public var client: Int
    public var command: Int
    public var axes: SpaceMouseAxes
    /// The buttons as a bitmap in the device's numbering; `SpaceMouseModel.buttons` names them.
    public var buttonBits: UInt32
    /// Uptime timestamp of the message (`clock_get_uptime` units).
    public var time: UInt64

    public init?(_ bytes: UnsafeRawBufferPointer) {
        guard bytes.count >= Self.size else { return nil }
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: u16(offset))) }
        func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
        client = Int(u16(2))
        command = Int(u16(4))
        time = UInt64(u32(12)) | UInt64(u32(16)) << 32
        axes = SpaceMouseAxes(x: i16(30), y: i16(32), z: i16(34), rx: i16(36), ry: i16(38), rz: i16(40))
        buttonBits = u32(44)
    }
}
