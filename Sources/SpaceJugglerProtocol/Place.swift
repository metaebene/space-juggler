import Foundation

/// Where Space Juggler's lock, socket, log and record of the newest broker live, per user (ADR-0001).
public struct BrokerPlace: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// `SPACE_JUGGLER_HOME` for tests, otherwise `~/Library/Application Support/Space Juggler`.
    public static var standard: BrokerPlace {
        if let home = ProcessInfo.processInfo.environment["SPACE_JUGGLER_HOME"] {
            return BrokerPlace(directory: URL(fileURLWithPath: home))
        }
        return BrokerPlace(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(SpaceJuggler.appName)"))
    }

    public var lock: URL { directory.appendingPathComponent("broker.lock") }
    /// A Unix socket path must stay under 104 bytes (docs/spike.md).
    public var socket: URL { directory.appendingPathComponent("broker.sock") }
    public var log: URL { directory.appendingPathComponent("broker.log") }
    /// The newest broker that ever ran: a client without a broker starts that one if it is newer than its own.
    public var newest: URL { directory.appendingPathComponent("newest.json") }

    /// How to start a broker: an app bundle (through Launch Services) or a command-line tool with arguments (tests).
    public struct Newest: Codable, Sendable, Equatable {
        public var version: Int
        public var path: String
        public var arguments: [String]

        public init(version: Int, path: String, arguments: [String] = []) {
            self.version = version
            self.path = path
            self.arguments = arguments
        }

        public var isApp: Bool { path.hasSuffix(".app") }

        public var exists: Bool {
            isApp ? FileManager.default.fileExists(atPath: path) : FileManager.default.isExecutableFile(atPath: path)
        }
    }

    public func readNewest() -> Newest? {
        guard let data = try? Data(contentsOf: newest) else { return nil }
        return try? JSONDecoder().decode(Newest.self, from: data)
    }

    /// Records a broker as the newest, unless a newer one is recorded whose program still exists.
    public func recordNewest(_ candidate: Newest) {
        if let known = readNewest(), known.version > candidate.version, known.exists { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(candidate).write(to: newest, options: .atomic)
    }

    /// Keeps the log small: above 512 KB it moves to `broker.log.1` (the broker calls this when it starts).
    public func rotateLog() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 512 * 1024 else { return }
        let old = directory.appendingPathComponent("broker.log.1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: log, to: old)
    }

    /// Appends a line, with time and process, to the broker log (for diagnosis; see `rotateLog`).
    public func appendLog(_ text: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let data = Data("\(formatter.string(from: Date())) [\(getpid())] \(text)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: log)
        }
    }
}
