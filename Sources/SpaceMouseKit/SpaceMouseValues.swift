import Foundation

/// Deflection of the SpaceMouse cap, as the input reports it. Native HID: raw device units, about ±350 per axis
/// (`SpaceMouseModel.axisFullScale`).
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

    /// One way the cap can move (stagehand ADR-0084), with the signs above.
    public enum Direction: String, CaseIterable, Sendable, Hashable, Codable {
        case slideRight, slideLeft, slideForward, slideBack, push, pull
        case tiltForward, tiltBack, tiltRight, tiltLeft, twistRight, twistLeft

        /// The axis (0 … 5: x y z rx ry rz) and which sign of it this direction is.
        public var axis: (index: Int, sign: Int) {
            switch self {
            case .slideRight: (0, 1)
            case .slideLeft: (0, -1)
            case .slideForward: (1, -1)
            case .slideBack: (1, 1)
            case .push: (2, 1)
            case .pull: (2, -1)
            case .tiltForward: (3, -1)
            case .tiltBack: (3, 1)
            case .tiltRight: (4, -1)
            case .tiltLeft: (4, 1)
            case .twistRight: (5, 1)
            case .twistLeft: (5, -1)
            }
        }

        /// What to do with the cap, as an instruction.
        public var instruction: String {
            switch self {
            case .slideRight: "Slide the cap to the right"
            case .slideLeft: "Slide the cap to the left"
            case .slideForward: "Slide the cap forward, away from you"
            case .slideBack: "Slide the cap back, towards you"
            case .push: "Push the cap down"
            case .pull: "Pull the cap up"
            case .tiltForward: "Tilt the cap forward"
            case .tiltBack: "Tilt the cap back"
            case .tiltRight: "Tilt the cap to the right"
            case .tiltLeft: "Tilt the cap to the left"
            case .twistRight: "Twist the cap clockwise"
            case .twistLeft: "Twist the cap counter-clockwise"
            }
        }
    }

    public static let axisNames = ["x", "y", "z", "rx", "ry", "rz"]

    /// How far the cap is moved in a direction, in raw units; 0 when it is moved the other way.
    public func along(_ direction: Direction) -> Int {
        let (index, sign) = direction.axis
        return max(0, all[index] * sign)
    }

    /// The same as a fraction of `fullScale`, 0 … 1.
    public func fraction(_ direction: Direction, fullScale: Int = deviceFullScale) -> Double {
        min(1, Double(along(direction)) / Double(max(1, fullScale)))
    }

    /// The direction the cap is moved furthest in; nil at rest. Ties go to the earlier direction.
    public var strongest: Direction? {
        var best: Direction?, most = 0
        for direction in Direction.allCases where along(direction) > most {
            best = direction
            most = along(direction)
        }
        return best
    }
}

/// The buttons held, by what they are, whichever model has them: each model says which bit of its button report is
/// which (`SpaceMouseModel.buttonBits`). Names as printed on the keys; the bigger models share 3Dconnexion's numbering
/// (`SpaceMouseModel.sharedNumbering`, docs/models.md). Bits 0 … 16 are those of protocol 1.
public struct SpaceMouseButtons: OptionSet, Sendable, Hashable, Codable, CaseIterable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
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
    /// The function keys of the SpacePilot, SpacePilot Pro and Enterprise beyond the Pro's four (docs/models.md).
    public static let key5 = SpaceMouseButtons(rawValue: 1 << 17)
    public static let key6 = SpaceMouseButtons(rawValue: 1 << 18)
    public static let key7 = SpaceMouseButtons(rawValue: 1 << 19)
    public static let key8 = SpaceMouseButtons(rawValue: 1 << 20)
    public static let key9 = SpaceMouseButtons(rawValue: 1 << 21)
    public static let key10 = SpaceMouseButtons(rawValue: 1 << 22)
    public static let key11 = SpaceMouseButtons(rawValue: 1 << 23)
    public static let key12 = SpaceMouseButtons(rawValue: 1 << 24)
    /// The views the bigger models have as keys of their own or as the long press of a view key.
    public static let viewLeft = SpaceMouseButtons(rawValue: 1 << 25)
    public static let viewBottom = SpaceMouseButtons(rawValue: 1 << 26)
    public static let viewBack = SpaceMouseButtons(rawValue: 1 << 27)
    public static let viewRollReverse = SpaceMouseButtons(rawValue: 1 << 28)
    public static let viewIso1 = SpaceMouseButtons(rawValue: 1 << 29)
    public static let viewIso2 = SpaceMouseButtons(rawValue: 1 << 30)
    /// The keyboard keys of the Enterprise.
    public static let enter = SpaceMouseButtons(rawValue: 1 << 31)
    public static let delete = SpaceMouseButtons(rawValue: 1 << 32)
    public static let tab = SpaceMouseButtons(rawValue: 1 << 33)
    public static let space = SpaceMouseButtons(rawValue: 1 << 34)
    /// The Enterprise's saved views V1 … V3.
    public static let view1 = SpaceMouseButtons(rawValue: 1 << 35)
    public static let view2 = SpaceMouseButtons(rawValue: 1 << 36)
    public static let view3 = SpaceMouseButtons(rawValue: 1 << 37)
    /// Sensitivity `+` and `−`, DOMINANT, PAN/ZOOM and CONFIG of the SpacePilot family and the SpaceExplorer.
    public static let plus = SpaceMouseButtons(rawValue: 1 << 38)
    public static let minus = SpaceMouseButtons(rawValue: 1 << 39)
    public static let dominant = SpaceMouseButtons(rawValue: 1 << 40)
    public static let panZoom = SpaceMouseButtons(rawValue: 1 << 41)
    public static let config = SpaceMouseButtons(rawValue: 1 << 42)

    /// The buttons protocol 1 knows (a `UInt32` there).
    public static let protocol1 = SpaceMouseButtons(rawValue: 0xFFFF_FFFF)

    public static let allCases: [SpaceMouseButtons] = (0...42).map { SpaceMouseButtons(rawValue: 1 << UInt64($0)) }

    /// Each button held, alone.
    public var each: [SpaceMouseButtons] { Self.allCases.filter { contains($0) } }

    /// The name of one button, as printed on the key.
    public var name: String { each.map { Self.names[$0] ?? "?" }.joined(separator: " + ") }

    private static let names: [SpaceMouseButtons: String] = [
        .left: "1 (left)", .right: "2 (right)", .key1: "1", .key2: "2", .key3: "3", .key4: "4", .menu: "MENU", .fit: "FIT",
        .viewTop: "T", .viewRight: "R", .viewFront: "F", .viewRoll: "Roll", .escape: "ESC", .shift: "SHIFT",
        .control: "CTRL", .alt: "ALT", .rotationLock: "Rotation lock", .key5: "5", .key6: "6", .key7: "7", .key8: "8",
        .key9: "9", .key10: "10", .key11: "11", .key12: "12", .viewLeft: "L", .viewBottom: "B", .viewBack: "BK",
        .viewRollReverse: "Roll back", .viewIso1: "ISO1", .viewIso2: "ISO2", .enter: "ENTER", .delete: "DEL", .tab: "TAB",
        .space: "SPACE", .view1: "V1", .view2: "V2", .view3: "V3", .plus: "+", .minus: "−", .dominant: "DOMINANT",
        .panZoom: "PAN/ZOOM", .config: "CONFIG",
    ]

    /// The two buttons a program uses that only knows two, among `all`: left and right where the device has them (the
    /// Compact), else MENU and FIT (the Pro, Space Glider ADR-0025), else keys 1 and 2 (the SpaceTraveler).
    public static func twoButtons(of all: SpaceMouseButtons) -> (left: SpaceMouseButtons, right: SpaceMouseButtons) {
        all.contains(.left) ? (.left, .right) : all.contains(.menu) ? (.menu, .fit) : (.key1, .key2)
    }

    /// Those held, as a program sees them that only knows two buttons: `.left` and `.right` for `pair`.
    public func asTwoButtons(_ pair: (left: SpaceMouseButtons, right: SpaceMouseButtons)) -> SpaceMouseButtons {
        var two: SpaceMouseButtons = []
        if contains(pair.left) { two.insert(.left) }
        if contains(pair.right) { two.insert(.right) }
        return two
    }
}

/// Decodes the input reports of every SpaceMouse model. From Kugelblitz's copy (itself ported from stagehand's
/// `SpaceMouseReport` via Spacer), with stagehand's battery, serial number and unknown bits. The report buffer includes
/// the report ID as byte 0.
public enum SpaceMouseReport {
    public static let translationReportID: UInt8 = 1
    public static let rotationReportID: UInt8 = 2
    public static let buttonReportID: UInt8 = 3
    /// The battery of the wireless models (`17 <percent> <flags>`, stagehand ADR-0090).
    public static let batteryReportID: UInt8 = 0x17
    /// Vendor feature report with the serial number of the SpaceMouse Wireless and the Compact (`serialFeatureReportID`).
    public static let serialReportID: UInt8 = 0x08

    /// The bits set in report 3, all of them (the Enterprise's reach bit 175); nil for other reports.
    public static func buttonBits(_ bytes: UnsafeBufferPointer<UInt8>) -> [Int]? {
        guard bytes.count >= 2, bytes[0] == buttonReportID else { return nil }
        return (0..<(bytes.count - 1) * 8).filter { bytes[1 + $0 / 8] & UInt8(1 << ($0 % 8)) != 0 }
    }

    /// Buttons held according to report 3, with the model's bits; nil for other reports.
    public static func buttons(_ bytes: UnsafeBufferPointer<UInt8>, model: SpaceMouseModel) -> SpaceMouseButtons? {
        buttonBits(bytes).map { model.buttons(bits: $0) }
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
