import Foundation

/// The broker's protocol: one JSON object per line over a Unix domain socket (ADR-0001). Public, so other programs can
/// be clients; every change that an older peer cannot read raises `protocolVersion`.
public enum Wire {
    public static let protocolVersion = 1
}

/// From a client, or from a newer broker that wants to take over.
public enum ClientMessage: Codable, Sendable, Equatable {
    /// First message of every connection. `claim` nil = only asking (status, takeover).
    case hello(protocolVersion: Int, processID: Int32, name: String, claim: Claim?)
    case claim(Claim)
    case status
    /// A broker of `version` asks the running one to hand over.
    case takeOver(version: Int)
}

/// From the broker.
public enum BrokerMessage: Codable, Sendable, Equatable {
    case welcome(brokerVersion: Int, protocolVersion: Int)
    /// This client now gets the SpaceMouse (true) or no longer (false).
    case holding(Bool)
    case axes(device: String, x: Int, y: Int, z: Int, rx: Int, ry: Int, rz: Int)
    case buttons(device: String, held: [String])
    case status(BrokerStatus)
    /// Answer to `takeOver`: the broker leaves (true) or stays because it is as new or newer (false).
    case handingOver(Bool)
}

public struct BrokerStatus: Codable, Sendable, Equatable {
    public struct Device: Codable, Sendable, Equatable {
        public var id: String
        public var model: String
        /// "open" or why not.
        public var state: String

        public init(id: String, model: String, state: String) {
            self.id = id
            self.model = model
            self.state = state
        }
    }

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

    public var brokerVersion: Int
    public var processID: Int32
    public var frontmostApp: String?
    public var devices: [Device]
    public var clients: [Client]

    public init(brokerVersion: Int, processID: Int32, frontmostApp: String?, devices: [Device], clients: [Client]) {
        self.brokerVersion = brokerVersion
        self.processID = processID
        self.frontmostApp = frontmostApp
        self.devices = devices
        self.clients = clients
    }
}

/// Where the broker's lock, socket and record of the newest broker live, per user.
public struct BrokerPlace: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// `SMK_HOME` for tests, otherwise Application Support.
    public static var standard: BrokerPlace {
        if let home = ProcessInfo.processInfo.environment["SMK_HOME"] {
            return BrokerPlace(directory: URL(fileURLWithPath: home))
        }
        return BrokerPlace(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Space Juggler"))
    }

    public var lock: URL { directory.appendingPathComponent("broker.lock") }
    public var socket: URL { directory.appendingPathComponent("broker.sock") }
    /// The newest broker that ever ran: a client without a broker starts that one if it is newer than its own.
    public var newest: URL { directory.appendingPathComponent("newest.json") }

    public struct Newest: Codable, Sendable, Equatable {
        public var version: Int
        public var path: String

        public init(version: Int, path: String) {
            self.version = version
            self.path = path
        }
    }

    public func readNewest() -> Newest? {
        guard let data = try? Data(contentsOf: newest) else { return nil }
        return try? JSONDecoder().decode(Newest.self, from: data)
    }

    /// Records a broker as the newest, unless a newer one is recorded whose program still exists.
    public func recordNewest(_ candidate: Newest) {
        if let known = readNewest(), known.version > candidate.version,
           FileManager.default.isExecutableFile(atPath: known.path) { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(candidate).write(to: newest, options: .atomic)
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
