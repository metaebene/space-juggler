import Foundation

/// A SpaceMouse model: what a device of it sends and which bit is which key. Matched by vendor **and** product ID
/// (ADR-0003). All send their axes in reports 1 and 2 or in one long report 1, their buttons in report 3, and take
/// output report 4 for the LED (ADR-0023, Kugelblitz ADR-0134). A device the catalog lacks is recognised by its report
/// descriptor (`recognise`, ADR-0005).
public struct SpaceMouseModel: Sendable, CustomStringConvertible {
    /// How this entry is known (ADR-0005).
    public enum Knowledge: String, Sendable, Codable {
        /// Checked at a device here: every key, the axes, the LED.
        case checked
        /// From public sources only (`docs/models.md`); nobody here has seen it work.
        case published
        /// Not in the catalog: built from the device's report descriptor.
        case guessed
    }

    public let vendorID: Int
    public let productID: Int
    public let name: String
    /// Which bit of the button report (bit 0 = the lowest bit of the byte after the report ID) is which button.
    public let buttonBits: [Int: SpaceMouseButtons]
    public let knowledge: Knowledge
    /// The logical maximum of the axes (raw units at full deflection).
    public let axisFullScale: Int
    /// One status LED, switched with output report 4 (`04 01` / `04 00`); the device does not report its state, so
    /// whoever writes it mirrors it (stagehand ADR-0083).
    public let hasStatusLED: Bool

    public init(vendorID: Int, productID: Int, name: String, buttonBits: [Int: SpaceMouseButtons],
                knowledge: Knowledge = .published, axisFullScale: Int = SpaceMouseAxes.deviceFullScale,
                hasStatusLED: Bool = true) {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.buttonBits = buttonBits
        self.knowledge = knowledge
        self.axisFullScale = axisFullScale
        self.hasStatusLED = hasStatusLED
    }

    public var description: String { String(format: "%@ (%04X:%04X, %@)", name, vendorID, productID, knowledge.rawValue) }

    /// Every button a device of this model has.
    public var buttons: SpaceMouseButtons { buttonBits.values.reduce([]) { $0.union($1) } }

    // MARK: - Checked at a device

    public static let compact = SpaceMouseModel(vendorID: 0x256F, productID: 0xC635, name: "SpaceMouse Compact",
                                                buttonBits: twoButtons, knowledge: .checked)
    /// From the Logitech years, hence Logitech's vendor ID. Report descriptor read from the IORegistry (2026-10-04):
    /// the Compact's reports, but a logical range of ±500 instead of ±350 (public dumps of other firmware say ±350).
    public static let spaceNavigator = SpaceMouseModel(vendorID: 0x046D, productID: 0xC626, name: "SpaceNavigator",
                                                       buttonBits: twoButtons, knowledge: .checked, axisFullScale: 500)
    /// Also from the Logitech years. The Compact's axes (±350) and LED; fifteen keys in a report 3 of six bytes, at
    /// 3Dconnexion's numbering shared with the bigger models, hence the gaps (stagehand ADR-0087: descriptor and every
    /// key checked at a device, 2026-10-05).
    public static let spaceMousePro = SpaceMouseModel(vendorID: 0x046D, productID: 0xC62B, name: "SpaceMouse Pro",
                                                      buttonBits: proBits, knowledge: .checked)
    /// The Bluetooth Edition, over Bluetooth and on its USB cable with the same IDs and descriptor: the Compact's two
    /// buttons, all six axes (±350) in one report 1 of twelve bytes (stagehand ADR-0090, ADR-0091).
    public static let spaceMouseWireless = SpaceMouseModel(vendorID: 0x256F, productID: 0xC63A,
                                                           name: "SpaceMouse Wireless", buttonBits: twoButtons,
                                                           knowledge: .checked)

    // MARK: - From public sources (docs/models.md)

    public static let spaceNavigatorNotebook = SpaceMouseModel(vendorID: 0x046D, productID: 0xC628,
                                                               name: "SpaceNavigator for Notebooks", buttonBits: twoButtons)
    /// Fifteen keys in a numbering of its own; Blender, PySpaceMouse, FreeCAD and Open CASCADE agree. Its "2D" key
    /// turns rotation off, PANEL opens the settings.
    public static let spaceExplorer = SpaceMouseModel(
        vendorID: 0x046D, productID: 0xC627, name: "SpaceExplorer",
        buttonBits: [0: .key1, 1: .key2, 2: .viewTop, 3: .viewLeft, 4: .viewRight, 5: .viewFront, 6: .escape, 7: .alt,
                     8: .shift, 9: .control, 10: .fit, 11: .menu, 12: .plus, 13: .minus, 14: .rotationLock])
    /// 21 keys and an LCD; no LED report (PySpaceMouse). Bits 16/17 as the majority of sources has them.
    public static let spacePilot = SpaceMouseModel(
        vendorID: 0x046D, productID: 0xC625, name: "SpacePilot",
        buttonBits: [0: .key1, 1: .key2, 2: .key3, 3: .key4, 4: .key5, 5: .key6, 6: .viewTop, 7: .viewLeft,
                     8: .viewRight, 9: .viewFront, 10: .escape, 11: .alt, 12: .shift, 13: .control, 14: .fit,
                     15: .menu, 16: .plus, 17: .minus, 18: .dominant, 19: .rotationLock, 20: .config],
        hasStatusLED: false)
    /// 31 keys at the shared numbering, bits 0 … 30.
    public static let spacePilotPro = SpaceMouseModel(vendorID: 0x046D, productID: 0xC629, name: "SpacePilot Pro",
                                                      buttonBits: sharedNumbering.filter { $0.key <= 30 })
    /// The first SpaceMouse Wireless (2013), on its cable and through its own receiver: two buttons, one report 1.
    public static let spaceMouseWirelessCable = SpaceMouseModel(vendorID: 0x256F, productID: 0xC62E,
                                                                name: "SpaceMouse Wireless (cable)", buttonBits: twoButtons)
    public static let spaceMouseWirelessReceiver = SpaceMouseModel(vendorID: 0x256F, productID: 0xC62F,
                                                                   name: "SpaceMouse Wireless (receiver)",
                                                                   buttonBits: twoButtons)
    /// The SpaceMouse Pro's keys at the same bits, one report 1 for all axes.
    public static let spaceMouseProWirelessCable = SpaceMouseModel(vendorID: 0x256F, productID: 0xC631,
                                                                   name: "SpaceMouse Pro Wireless (cable)",
                                                                   buttonBits: proBits)
    public static let spaceMouseProWirelessReceiver = SpaceMouseModel(vendorID: 0x256F, productID: 0xC632,
                                                                      name: "SpaceMouse Pro Wireless (receiver)",
                                                                      buttonBits: proBits)
    /// The Bluetooth Edition of the Pro Wireless: one product ID on cable and Bluetooth, like the SpaceMouse Wireless.
    public static let spaceMouseProWireless = SpaceMouseModel(vendorID: 0x256F, productID: 0xC638,
                                                              name: "SpaceMouse Pro Wireless", buttonBits: proBits)
    /// 31 keys at the shared numbering up to bit 175; long presses come only in reports 0x1C/0x1D (not read here).
    public static let enterprise = SpaceMouseModel(vendorID: 0x256F, productID: 0xC633, name: "SpaceMouse Enterprise",
                                                   buttonBits: enterpriseBits)

    public static let known: [SpaceMouseModel] = [
        .compact, .spaceNavigator, .spaceMousePro, .spaceMouseWireless,
        .spaceNavigatorNotebook, .spaceExplorer, .spacePilot, .spacePilotPro, .spaceMouseWirelessCable,
        .spaceMouseWirelessReceiver, .spaceMouseProWirelessCable, .spaceMouseProWirelessReceiver,
        .spaceMouseProWireless, .enterprise,
    ]

    // MARK: - Recognising

    /// Logitech (the early models) and 3Dconnexion.
    public static let vendorIDs = [0x046D, 0x256F]
    /// One HID device per pairing slot, each with the reports of the device paired there (docs/models.md).
    public static let universalReceiverProductID = 0xC652
    /// 3Dconnexion devices that are no SpaceMouse: CadMice, Keyboard Pro, Numpad Pro, and the virtual mouse 3Dconnexion's
    /// driver makes (docs/models.md).
    public static let ignored: Set<Int> = [0xC650, 0xC651, 0xC654, 0xC655, 0xC656, 0xC657, 0xC658, 0xC664, 0xC665,
                                           0xC668, 0xC671]

    /// The model of a device: the catalog's entry, else one built from its report descriptor if that is a
    /// Multi-axis Controller (ADR-0005); nil for anything else. The axis range and the LED follow the descriptor.
    public static func recognise(vendorID: Int, productID: Int, product: String?,
                                 descriptor: HIDReportDescriptor?) -> SpaceMouseModel? {
        guard vendorIDs.contains(vendorID), !(vendorID == 0x256F && ignored.contains(productID)) else { return nil }
        let range = descriptor?.axisLogicalMaximum.flatMap { $0 > 0 ? $0 : nil }
        if let model = matching(vendorID: vendorID, productID: productID) {
            return SpaceMouseModel(vendorID: vendorID, productID: productID, name: model.name, buttonBits: model.buttonBits,
                                   knowledge: model.knowledge, axisFullScale: range ?? model.axisFullScale,
                                   hasStatusLED: descriptor.map(\.hasLED) ?? model.hasStatusLED)
        }
        guard let descriptor, descriptor.isMultiAxisController else { return nil }
        let bits = Set(descriptor.buttonUsages.map { $0 - 1 })
        let buttonBits = bits.count <= 2 && bits.isSubset(of: [0, 1])
            ? twoButtons.filter { bits.contains($0.key) }
            : sharedNumbering.filter { bits.contains($0.key) }
        let receiver = vendorID == 0x256F && productID == universalReceiverProductID
        let name = receiver
            ? (bits.count > 2 ? "SpaceMouse Pro Wireless" : "SpaceMouse Wireless") + " (Universal Receiver)"
            : product.flatMap { $0.isEmpty ? nil : $0 } ?? String(format: "SpaceMouse %04X:%04X", vendorID, productID)
        return SpaceMouseModel(vendorID: vendorID, productID: productID, name: name, buttonBits: buttonBits,
                               knowledge: receiver ? .published : .guessed, axisFullScale: range ?? SpaceMouseAxes.deviceFullScale,
                               hasStatusLED: descriptor.hasLED)
    }

    public static func matching(vendorID: Int, productID: Int) -> SpaceMouseModel? {
        known.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// The model behind a product ID the 3DxWare driver names (it gives no vendor ID); the known models' product IDs
    /// differ.
    public static func matching(productID: Int) -> SpaceMouseModel? {
        known.first { $0.productID == productID }
    }

    // MARK: - Buttons

    private static let twoButtons: [Int: SpaceMouseButtons] = [0: .left, 1: .right]

    /// 3Dconnexion's numbering of the keys of its bigger models: the same bit is the same key wherever it exists
    /// (SpaceMouse Pro checked; SpacePilot Pro and Enterprise from Blender, spacenavd, PySpaceMouse, docs/models.md).
    public static let sharedNumbering: [Int: SpaceMouseButtons] = [
        0: .menu, 1: .fit, 2: .viewTop, 3: .viewLeft, 4: .viewRight, 5: .viewFront, 6: .viewBottom, 7: .viewBack,
        8: .viewRoll, 9: .viewRollReverse, 10: .viewIso1, 11: .viewIso2,
        12: .key1, 13: .key2, 14: .key3, 15: .key4, 16: .key5, 17: .key6, 18: .key7, 19: .key8, 20: .key9, 21: .key10,
        22: .escape, 23: .alt, 24: .shift, 25: .control, 26: .rotationLock, 27: .panZoom, 28: .dominant, 29: .plus,
        30: .minus, 35: .enter, 36: .delete, 76: .key11, 77: .key12, 102: .view1, 103: .view2, 104: .view3,
        174: .tab, 175: .space,
    ]

    private static let proBits = sharedNumbering.filter { [0, 1, 2, 4, 5, 8, 12, 13, 14, 15, 22, 23, 24, 25, 26].contains($0.key) }
    private static let enterpriseBits = sharedNumbering.filter {
        [0, 1, 2, 4, 5, 8, 10, 22, 23, 24, 25, 26, 35, 36, 76, 77, 102, 103, 104, 174, 175].contains($0.key) || (12...21).contains($0.key)
    }

    /// The Wireless (BT editions) take output report 4 over Bluetooth, but light the LED only on the USB cable
    /// (stagehand ADR-0091, seen at the device; the Pro Wireless BT assumed alike).
    public var statusLEDNeedsCable: Bool { vendorID == 0x256F && [0xC63A, 0xC638].contains(productID) }

    /// The vendor feature report that carries the serial number, for the models whose HID device has none on any
    /// transport: the Wireless (printed on its label, stagehand ADR-0092) and the Compact (different on two devices,
    /// taken as its serial number, docs/serial-report.md); asked on every 3Dconnexion model but the Universal Receiver,
    /// whose slots might all answer with the receiver's (ADR-0005). The SpaceNavigator and the SpaceMouse Pro declare it
    /// too, but leave it empty. The only feature report read in use, and only with GET.
    public var serialFeatureReportID: UInt8? {
        vendorID == 0x256F && productID != Self.universalReceiverProductID ? SpaceMouseReport.serialReportID : nil
    }

    /// The two buttons a program uses that only knows two: the Compact's left and right, else MENU and FIT
    /// (Space Glider ADR-0025).
    public var twoButtons: (left: SpaceMouseButtons, right: SpaceMouseButtons) {
        buttons.contains(.left) ? (.left, .right) : (.menu, .fit)
    }

    /// `held` as a program sees it that only knows two buttons: `.left` and `.right` (`twoButtons`).
    public func asTwoButtons(_ held: SpaceMouseButtons) -> SpaceMouseButtons {
        var two: SpaceMouseButtons = []
        if held.contains(twoButtons.left) { two.insert(.left) }
        if held.contains(twoButtons.right) { two.insert(.right) }
        return two
    }

    /// The buttons held according to a bitmap in the device's numbering (report 3, or the driver's state).
    public func buttons(_ bitmap: UInt64) -> SpaceMouseButtons {
        buttons(bits: (0..<64).filter { bitmap & 1 << UInt64($0) != 0 })
    }

    /// The buttons held according to the bits set in the device's numbering.
    public func buttons(bits: some Sequence<Int>) -> SpaceMouseButtons {
        bits.reduce(into: []) { held, bit in
            if let button = buttonBits[bit] { held.insert(button) }
        }
    }
}

extension SpaceMouseModel: Equatable {
    /// The same model: the same IDs and name (a Universal Receiver's slots differ by what is paired).
    public static func == (a: SpaceMouseModel, b: SpaceMouseModel) -> Bool {
        a.vendorID == b.vendorID && a.productID == b.productID && a.name == b.name
    }
}
