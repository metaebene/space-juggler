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
///
/// Never blocks: the socket is non-blocking, and what the peer has not taken yet waits here. A peer that stops reading
/// (a hung app, or a socket it dropped without closing, 2026-10-20) is dropped once `backlogLimit` is waiting, instead of
/// stopping the main thread in `write` until it reads again.
@MainActor
public final class LineConnection<Outgoing: Encodable, Incoming: Decodable> {
    public let fd: Int32
    /// About five seconds of a SpaceMouse's motion; nobody wants it later than that.
    public static var backlogLimit: Int { 64 * 1024 }
    private let descriptor: Descriptor
    private var source: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var backlog = Data()
    private var decoder = LineDecoder<Incoming>()
    private var closed = false
    public var onMessage: (Incoming) -> Void = { _ in }
    public var onClose: () -> Void = {}
    /// Closed because the peer did not take what was sent (`backlogLimit`).
    public private(set) var stalled = false

    public init(fd: Int32) {
        self.fd = fd
        descriptor = Descriptor(fd)
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    /// Dropping a connection without `close()` closes it too, so the peer is told (instead of filling up a socket
    /// nobody reads any more).
    deinit {
        writer?.cancel()
        source?.cancel()
    }

    public func start() {
        guard !closed else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readAvailable() } }
        source.setCancelHandler { [descriptor] in _ = descriptor }
        self.source = source
        source.resume()
    }

    public func send(_ message: Outgoing) {
        guard !closed else { return }
        backlog.append(LineEncoder.encode(message))
        if writer == nil { flush() }
        guard !closed else { return }
        if backlog.count > Self.backlogLimit {
            stalled = true
            close()
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        backlog = Data()
        writer?.cancel()
        writer = nil
        source?.cancel()
        source = nil
        onClose()
    }

    /// Writes what the socket takes; waits for room if something is left.
    private func flush() {
        while !backlog.isEmpty {
            let count = backlog.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                backlog.removeFirst(count)
            } else if count < 0, errno == EINTR {
                continue
            } else if count < 0, errno == EAGAIN {
                break
            } else {
                return close()
            }
        }
        if backlog.isEmpty {
            writer?.cancel()
            writer = nil
        } else if writer == nil {
            let writer = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
            writer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.flush() } }
            writer.setCancelHandler { [descriptor] in _ = descriptor }
            self.writer = writer
            writer.resume()
        }
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &buffer, buffer.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else { return close() }
        for message in decoder.feed(Data(buffer[0..<count])) { onMessage(message) }
    }
}

/// Closes the socket once the connection and every dispatch source on it are done with it (a source's cancel handler
/// holds it), never while one is still registered.
private final class Descriptor: Sendable {
    let fd: Int32
    init(_ fd: Int32) { self.fd = fd }
    deinit { Darwin.close(fd) }
}
