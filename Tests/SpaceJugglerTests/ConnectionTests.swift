import Foundation
import Testing
import SpaceJugglerProtocol

/// A peer that stops reading must never stop the sender (Space Juggler hung in `write`, 2026-10-20).
@MainActor
struct ConnectionTests {
    private func pair() -> (Int32, Int32) {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        return (fds[0], fds[1])
    }

    private let motion = BrokerMessage.axes(device: "serial:Z1", axes: SpaceMouseAxes(x: 350, y: -2, z: 151, rx: 0, ry: 1, rz: -350))

    @Test func aPeerThatDoesNotReadIsDroppedInsteadOfBlocking() {
        let (ours, theirs) = pair()
        defer { close(theirs) }
        let connection = LineConnection<BrokerMessage, ClientMessage>(fd: ours)
        var closed = false
        connection.onClose = { closed = true }
        connection.start()
        for _ in 0..<10_000 where !closed { connection.send(motion) }
        #expect(closed)
        #expect(connection.stalled)
    }

    @Test func aSlowPeerGetsEverythingInOrder() async throws {
        let (ours, theirs) = pair()
        let sender = LineConnection<BrokerMessage, ClientMessage>(fd: ours)
        let receiver = LineConnection<ClientMessage, BrokerMessage>(fd: theirs)
        var received: [BrokerMessage] = []
        receiver.onMessage = { received.append($0) }
        sender.start()
        // More than the socket takes at once, less than the backlog limit: sent before the receiver reads anything.
        let messages = (0..<400).map { BrokerMessage.axes(device: "serial:Z1", axes: SpaceMouseAxes(x: $0, y: 0, z: 0, rx: 0, ry: 0, rz: 0)) }
        messages.forEach(sender.send)
        #expect(!sender.stalled)
        receiver.start()
        for _ in 0..<200 where received.count < messages.count { try await Task.sleep(for: .milliseconds(10)) }
        #expect(received == messages)
    }

    @Test func droppingAConnectionClosesTheSocket() async throws {
        let (ours, theirs) = pair()
        defer { close(theirs) }
        var connection: LineConnection<BrokerMessage, ClientMessage>? = .init(fd: ours)
        connection?.start()
        connection = nil
        // The socket closes once the read source's cancel handler has run on the main queue.
        _ = fcntl(theirs, F_SETFL, O_NONBLOCK)
        var byte: UInt8 = 0
        var count = read(theirs, &byte, 1)
        for _ in 0..<200 where count < 0 {
            try await Task.sleep(for: .milliseconds(10))
            count = read(theirs, &byte, 1)
        }
        #expect(count == 0)
    }
}
