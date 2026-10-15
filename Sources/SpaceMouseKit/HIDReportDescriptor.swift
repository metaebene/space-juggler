import Foundation

/// A HID report descriptor, parsed far enough to tell what a SpaceMouse sends and takes (ADR-0005): its reports with
/// their lengths and fields, the application collections, and from those the axis range, the buttons, the LED and the
/// feature reports. Pure; the bytes come from the IORegistry (`ReportDescriptor`).
public struct HIDReportDescriptor: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable { case input, output, feature }

    public struct Usage: Sendable, Hashable, Codable {
        public var page: Int
        public var id: Int
        public init(page: Int, id: Int) { self.page = page; self.id = id }
    }

    /// One main item: `count` elements of `size` bits.
    public struct Field: Sendable, Equatable {
        /// One usage per element; shorter lists repeat their last usage (HID 6.2.2.8). Empty for padding.
        public var usages: [Usage]
        public var logicalMinimum: Int
        public var logicalMaximum: Int
        public var size: Int
        public var count: Int
        /// The main item's data bits: 0 constant, 1 variable, 2 relative.
        public var flags: Int

        public var isConstant: Bool { flags & 0x01 != 0 }
        public var isVariable: Bool { flags & 0x02 != 0 }
        public var isRelative: Bool { flags & 0x04 != 0 }

        /// The usage of element `index`.
        public func usage(_ index: Int) -> Usage? {
            usages.isEmpty ? nil : usages[min(index, usages.count - 1)]
        }
    }

    public struct Report: Sendable, Equatable {
        /// 0 for a descriptor without report IDs.
        public var id: UInt8
        public var kind: Kind
        public var fields: [Field] = []

        public var bits: Int { fields.reduce(0) { $0 + $1.size * $1.count } }
        /// In bytes, the report ID included as IOKit hands reports over.
        public var length: Int { (bits + 7) / 8 + (id == 0 ? 0 : 1) }
    }

    public private(set) var reports: [Report] = []
    /// The usages of the application collections, in order.
    public private(set) var applications: [Usage] = []

    /// Generic Desktop / Multi-axis Controller, the application collection of every SpaceMouse.
    public static let multiAxisController = Usage(page: 0x01, id: 0x08)
    static let buttonPage = 0x09
    static let ledPage = 0x08
    static let genericIndicator = 0x4B

    /// Nil when the bytes end in the middle of an item.
    public init?(_ bytes: [UInt8]) {
        struct Globals {
            var usagePage = 0, logicalMinimum = 0, logicalMaximum = 0, size = 0, count = 0
            /// The bytes the logical maximum came in, for reading it unsigned.
            var maximumBytes = 1
            var reportID: UInt8 = 0
        }
        var globals = Globals()
        var stack: [Globals] = []
        var usages: [Usage] = []
        var minimum: Usage?
        var index = 0

        func usage(_ value: UInt32, _ size: Int, page: Int) -> Usage {
            size == 4 ? Usage(page: Int(value >> 16), id: Int(value & 0xFFFF)) : Usage(page: page, id: Int(value))
        }

        while index < bytes.count {
            let prefix = bytes[index]
            if prefix == 0xFE {                                   // long item: skipped
                guard index + 2 < bytes.count else { return nil }
                index += 3 + Int(bytes[index + 1])
                continue
            }
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            guard index + size < bytes.count else { return nil }
            let data = (0..<size).reduce(UInt32(0)) { $0 | UInt32(bytes[index + 1 + $1]) << (8 * $1) }
            let signed: Int = switch size {
            case 1: Int(Int8(truncatingIfNeeded: data))
            case 2: Int(Int16(truncatingIfNeeded: data))
            case 4: Int(Int32(bitPattern: data))
            default: 0
            }
            index += 1 + size
            let tag = prefix >> 4
            switch (prefix >> 2) & 0x03 {
            case 0:                                               // main
                switch tag {
                case 0x8, 0x9, 0xB:
                    let kind: Kind = tag == 0x8 ? .input : tag == 0x9 ? .output : .feature
                    // A logical maximum read as negative beside a non-negative minimum was meant unsigned.
                    var maximum = globals.logicalMaximum
                    if globals.logicalMinimum >= 0, maximum < 0 { maximum += 1 << (8 * globals.maximumBytes) }
                    let field = Field(usages: usages, logicalMinimum: globals.logicalMinimum, logicalMaximum: maximum,
                                      size: globals.size, count: globals.count, flags: Int(data))
                    if let at = reports.firstIndex(where: { $0.id == globals.reportID && $0.kind == kind }) {
                        reports[at].fields.append(field)
                    } else {
                        reports.append(Report(id: globals.reportID, kind: kind, fields: [field]))
                    }
                case 0xA:
                    if data == 0x01, let first = usages.first { applications.append(first) }
                default:
                    break
                }
                usages = []
                minimum = nil
            case 1:                                               // global
                switch tag {
                case 0x0: globals.usagePage = Int(data)
                case 0x1: globals.logicalMinimum = signed
                case 0x2: globals.logicalMaximum = signed; globals.maximumBytes = size
                case 0x7: globals.size = Int(data)
                case 0x8: globals.reportID = UInt8(truncatingIfNeeded: data)
                case 0x9: globals.count = Int(data)
                case 0xA: stack.append(globals)
                case 0xB: if let popped = stack.popLast() { globals = popped }
                default: break
                }
            case 2:                                               // local
                switch tag {
                case 0x0: usages.append(usage(data, size, page: globals.usagePage))
                case 0x1: minimum = usage(data, size, page: globals.usagePage)
                case 0x2:
                    let maximum = usage(data, size, page: globals.usagePage)
                    if let minimum, minimum.id <= maximum.id, maximum.id - minimum.id < 1024 {
                        usages += (minimum.id...maximum.id).map { Usage(page: minimum.page, id: $0) }
                    }
                default: break
                }
            default:
                break
            }
        }
    }

    public func report(_ id: UInt8, _ kind: Kind) -> Report? {
        reports.first { $0.id == id && $0.kind == kind }
    }

    /// Whether one of the application collections is a Multi-axis Controller.
    public var isMultiAxisController: Bool { applications.contains(Self.multiAxisController) }

    /// The largest logical maximum of the six axes (Generic Desktop X … Rz) in an input report.
    public var axisLogicalMaximum: Int? {
        let axes = 0x30...0x35
        return reports.filter { $0.kind == .input }.flatMap(\.fields).filter { field in
            !field.isConstant && (0..<field.count).contains { field.usage($0).map { $0.page == 0x01 && axes.contains($0.id) } ?? false }
        }.map(\.logicalMaximum).max()
    }

    /// Whether the axes are declared relative (they are absolute in fact on every SpaceMouse, docs/models.md).
    public var axesDeclaredRelative: Bool {
        reports.filter { $0.kind == .input }.flatMap(\.fields).contains { field in
            field.isRelative && field.usages.contains { $0.page == 0x01 && (0x30...0x35).contains($0.id) }
        }
    }

    /// The buttons of the input reports by usage (1 = the first), in order: bit n of report 3 is usage n + 1.
    public var buttonUsages: [Int] {
        reports.filter { $0.kind == .input }.flatMap(\.fields).filter { !$0.isConstant }.flatMap { field -> [Int] in
            guard field.usages.contains(where: { $0.page == Self.buttonPage }) else { return [] }
            if field.isVariable {
                return (0..<field.count).compactMap { field.usage($0) }.filter { $0.page == Self.buttonPage }.map(\.id)
            }
            // An array: every usage it lists can be reported.
            return field.usages.filter { $0.page == Self.buttonPage }.map(\.id)
        }
    }

    /// Whether an output report carries an indicator LED (report 4 on every SpaceMouse that has one).
    public var hasLED: Bool {
        reports.contains { report in
            report.kind == .output && report.fields.contains { $0.usages.contains(Usage(page: Self.ledPage, id: Self.genericIndicator)) }
        }
    }

    /// The IDs of the feature reports, in order.
    public var featureReportIDs: [UInt8] { reports.filter { $0.kind == .feature }.map(\.id) }
}
