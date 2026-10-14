import Foundation
@_exported import SpaceMouseKit

/// Constants of this package's Space Juggler (ADR-0001, ADR-0002).
public enum SpaceJuggler {
    /// Version of the broker built from this package. A running broker hands over only to a higher one; a client
    /// that meets a lower one starts its own. Raise it with every release of the package.
    public static let version = 1
    /// Raised with every change of the messages that an older peer cannot read.
    public static let protocolVersion = 1
    public static let bundleIdentifier = "me.metaebene.SpaceJuggler"
    public static let appName = "Space Juggler"
}

/// What a client wants from Space Juggler (ADR-0001).
public struct Claim: Codable, Sendable, Equatable {
    /// Bundle IDs of the apps for which the client wants the SpaceMouse while one of them is frontmost: its own app
    /// (Kugelblitz), the app it lives in (Space Shuttle in REAPER) or the apps it steers (Space Glider).
    public var apps: [String]
    /// Whether it also wants the SpaceMouse while none of those apps is frontmost (Stagehand; Kugelblitz with "keep in
    /// background").
    public var background: Bool

    public init(apps: [String], background: Bool = false) {
        self.apps = apps
        self.background = background
    }
}

/// A SpaceMouse as Space Juggler knows it; sent to every client, holder or not (ADR-0003).
public struct SpaceMouseDevice: Codable, Sendable, Equatable, Identifiable {
    /// `serial:<S/N>`, `bt:<address>` or `port:<vid>:<pid>@<location>` (ADR-0003).
    public var id: String
    public var vendorID: Int
    public var productID: Int
    public var name: String
    /// "USB" or "Bluetooth", as IOKit says.
    public var transport: String
    public var serialNumber: String?
    public var battery: Int?
    public var charging: Bool?
    /// Turned on in Space Juggler's menu; input of a device that is off reaches nobody.
    public var enabled: Bool
    /// "open", "closed" or why it could not be opened.
    public var state: String
    /// The LED as last written (the device does not report it); nil = unknown.
    public var led: Bool?

    public init(id: String, vendorID: Int, productID: Int, name: String, transport: String, serialNumber: String? = nil,
                battery: Int? = nil, charging: Bool? = nil, enabled: Bool = true, state: String = "closed", led: Bool? = nil) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.transport = transport
        self.serialNumber = serialNumber
        self.battery = battery
        self.charging = charging
        self.enabled = enabled
        self.state = state
        self.led = led
    }

    public var model: SpaceMouseModel? { SpaceMouseModel.matching(vendorID: vendorID, productID: productID) }
    public var isBluetooth: Bool { transport.caseInsensitiveCompare("Bluetooth") == .orderedSame }
}

public struct Hello: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    /// The Space Juggler version the client brings.
    public var version: Int
    public var processID: Int32
    public var name: String
    /// nil = only asking (status, takeover).
    public var claim: Claim?

    public init(protocolVersion: Int = SpaceJuggler.protocolVersion, version: Int, processID: Int32, name: String,
                claim: Claim?) {
        self.protocolVersion = protocolVersion
        self.version = version
        self.processID = processID
        self.name = name
        self.claim = claim
    }
}

/// From a client, or from a newer broker that wants to take over.
public enum ClientMessage: Codable, Sendable, Equatable {
    /// First message of every connection.
    case hello(Hello)
    case claim(Claim)
    /// Any client may switch a device's LED (ADR-0003).
    case setLED(device: String, on: Bool)
    case status
    /// A broker of `version` asks the running one to hand over.
    case takeOver(version: Int)
}

/// From Space Juggler.
public enum BrokerMessage: Codable, Sendable, Equatable {
    case welcome(version: Int, protocolVersion: Int)
    /// Every device, after the welcome and on every change, to every client.
    case devices([SpaceMouseDevice])
    /// This client now gets the input (true) or no longer (false).
    case holding(Bool)
    case axes(device: String, axes: SpaceMouseAxes)
    /// The buttons held on one device, by what they are.
    case buttons(device: String, held: SpaceMouseButtons)
    case status(BrokerStatus)
    /// Answer to `takeOver`: the broker leaves (true) or stays because it is as new or newer (false).
    case handingOver(Bool)
}

public struct BrokerStatus: Codable, Sendable, Equatable {
    public struct Client: Codable, Sendable, Equatable {
        public var id: Int
        public var name: String
        public var processID: Int32
        public var claim: Claim
        public var holds: Bool

        public init(id: Int, name: String, processID: Int32, claim: Claim, holds: Bool) {
            self.id = id
            self.name = name
            self.processID = processID
            self.claim = claim
            self.holds = holds
        }
    }

    public var version: Int
    public var processID: Int32
    public var frontmostApp: String?
    public var devices: [SpaceMouseDevice]
    public var clients: [Client]

    public init(version: Int, processID: Int32, frontmostApp: String?, devices: [SpaceMouseDevice], clients: [Client]) {
        self.version = version
        self.processID = processID
        self.frontmostApp = frontmostApp
        self.devices = devices
        self.clients = clients
    }
}

/// Splits a byte stream into lines and decodes each as `Message`.
public struct LineDecoder<Message: Decodable> {
    private var pending = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> [Message] {
        pending.append(data)
        var messages: [Message] = []
        while let end = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<end]
            pending.removeSubrange(pending.startIndex...end)
            if let message = try? JSONDecoder().decode(Message.self, from: line) { messages.append(message) }
        }
        return messages
    }
}

public enum LineEncoder {
    public static func encode<Message: Encodable>(_ message: Message) -> Data {
        var data = (try? JSONEncoder().encode(message)) ?? Data()
        data.append(0x0A)
        return data
    }
}
