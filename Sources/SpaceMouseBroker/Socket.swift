import Foundation

/// Unix domain sockets for the broker (ADR-0001). Everything runs on the main queue.
public enum UnixSocket {
    private static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// Binds and listens; removes a stale socket file first (only call while holding the broker lock).
    public static func listen(at path: String) -> Int32? {
        guard var address = address(path) else { return nil }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            close(fd)
            return nil
        }
        chmod(path, 0o600)
        return fd
    }

    public static func connect(to path: String) -> Int32? {
        guard var address = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        return fd
    }
}

/// One side of a connection: sends `Outgoing`, receives `Incoming`, one JSON object per line.
@MainActor
public final class LineConnection<Outgoing: Encodable, Incoming: Decodable> {
    public let fd: Int32
    private var source: DispatchSourceRead?
    private var decoder = LineDecoder<Incoming>()
    public var onMessage: (Incoming) -> Void = { _ in }
    public var onClose: () -> Void = {}

    public init(fd: Int32) {
        self.fd = fd
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    public func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        source.setCancelHandler { [fd] in Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    public func send(_ message: Outgoing) {
        let data = LineEncoder.encode(message)
        let written = data.withUnsafeBytes { raw -> Int in
            var offset = 0
            while offset < raw.count {
                let count = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if count <= 0 { return -1 }
                offset += count
            }
            return offset
        }
        if written < 0 { close() }
    }

    public func close() {
        guard let source else { return }
        self.source = nil
        source.cancel()
        onClose()
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return close() }
        for message in decoder.feed(Data(buffer[0..<count])) { onMessage(message) }
    }
}
