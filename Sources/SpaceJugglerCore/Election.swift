import Foundation
import SpaceJugglerProtocol

/// One broker at a time, the newest wins (ADR-0001): the broker that holds `broker.lock` runs; a newer one asks it to
/// hand over and waits for the lock.
public enum Election {
    public enum Outcome: Equatable {
        /// This broker runs; keep the file open for as long as it does (the lock goes with the process).
        case elected(lockFile: Int32)
        /// A broker of this version or newer runs and stays.
        case stays(runningVersion: Int)
        /// The lock is held but nobody answers, or the old broker does not let go.
        case failed(String)
    }

    /// Blocks for up to about 7 s (startup of the running broker, then its handover).
    public static func run(place: BrokerPlace, version: Int, log: (String) -> Void) -> Outcome {
        place.ensureDirectory()
        let fd = open(place.lock.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return .failed("cannot open \(place.lock.path): \(String(cString: strerror(errno)))") }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return .elected(lockFile: fd) }

        var answer: (running: Int, leaves: Bool)?
        for _ in 0..<20 where answer == nil {
            answer = askToHandOver(place: place, version: version)
            if answer == nil { usleep(100_000) }
        }
        guard let answer else {
            close(fd)
            return .failed("lock held, but no broker answers")
        }
        guard answer.leaves else {
            close(fd)
            return .stays(runningVersion: answer.running)
        }
        log("running broker v\(answer.running) hands over to v\(version)")
        let started = Date()
        while Date().timeIntervalSince(started) < 5 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                log("lock taken after \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                return .elected(lockFile: fd)
            }
            usleep(20_000)
        }
        close(fd)
        return .failed("old broker did not let go of the lock")
    }

    /// Synchronous: hello and takeOver, then wait for the answer.
    private static func askToHandOver(place: BrokerPlace, version: Int) -> (running: Int, leaves: Bool)? {
        guard let fd = UnixSocket.connect(to: place.socket.path) else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let hello = Hello(version: version, processID: getpid(), name: "Space Juggler v\(version)", claim: nil)
        for message in [ClientMessage.hello(hello), .takeOver(version: version)] {
            let data = LineEncoder.encode(message)
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
        var decoder = LineDecoder<BrokerMessage>()
        var running: Int?
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { return nil }
            for message in decoder.feed(Data(buffer[0..<count])) {
                switch message {
                case .welcome(let brokerVersion, _): running = brokerVersion
                case .handingOver(let leaves): return (running ?? 0, leaves)
                default: break
                }
            }
        }
    }
}
