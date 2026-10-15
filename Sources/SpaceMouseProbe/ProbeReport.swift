import Foundation
import SpaceJugglerClient

/// What SpaceMouse Probe found out about one device, as sent in a device report (ADR-0006, `format` 1). Bytes are
/// written as hex, report ID first.
struct ProbeReport: Codable {
    var format = 1
    var tool: String
    var date: Date
    var macOS: String
    var spaceJuggler: Int?
    /// 3Dconnexion's helper held the device (ADR-0004): no keys or axes could be recorded.
    var driverRunning: Bool
    var device: Device
    var keys: Keys
    var axes: Axes
    var led: LED?
    var label: Label
    var batteryReports: [String]
    /// The first report of every input report ID other than axes, buttons and battery.
    var otherInputReports: [String: String]
    var notes: String

    struct Device: Codable {
        var name: String
        var knowledge: String?
        var vendorID: String
        var productID: String
        var transport: String
        var identity: String
        var serialNumberRead: String?
        var properties: [String: String]
        var reportDescriptor: String
        var featureReports: [String: String]
        var featureReportsVia: String?
        var reports: [String]
        var axisMaximum: Int?
        var axesDeclaredRelative: Bool?
        var buttonUsages: [Int]
        var hasLED: Bool?
    }

    struct Keys: Codable {
        struct Key: Codable {
            var bit: Int
            var label: String
            /// What the catalog calls this bit, if anything.
            var catalog: String?
        }
        var declared: Int
        var found: [Key]
        /// The user said there are no more keys.
        var complete: Bool
    }

    struct Axes: Codable {
        struct Direction: Codable {
            var direction: String
            var axis: String
            var sign: Int
            var peak: Int
            var asExpected: Bool
        }
        var fullScale: Int
        var directions: [Direction]
        /// The lowest and highest value seen per axis.
        var range: [String: [Int]]
    }

    struct LED: Codable {
        var lit: Bool?
        var wentOut: Bool?
    }

    struct Label: Codable {
        var name: String
        var serialNumber: String
        var noSerialNumberPrinted: Bool
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

    var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)) ?? Data()
    }
}
