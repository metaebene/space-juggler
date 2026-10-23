import Foundation
import Testing
@testable import SpaceJugglerCore
import SpaceJugglerClient

/// A broker without devices and its clients, all in this process on the main queue (ADR-0001): who holds, who waits,
/// handover and lingering. Election against a live broker cannot be tested here, as `Election.run` blocks the main
/// thread the broker would answer from (`Scripts/spike-scenario.sh` covers it with processes).
@MainActor
struct BrokerTests {
    /// What a client saw, in order.
    @MainActor
    final class Recorder {
        var events: [SpaceJugglerConnection.Event] = []
        var holds: Bool? { events.lazy.compactMap { if case .holding(let holds) = $0 { holds } else { nil } }.last }
        var connected: Bool { events.contains { if case .connected = $0 { true } else { false } } }
    }

    /// One elected broker in a directory of its own, left again through a handover at the end.
    @MainActor
    final class Harness {
        let place: BrokerPlace
        let broker: Broker
        private(set) var left = false
        private(set) var log: [String] = []
        private var clients: [SpaceJugglerConnection] = []

        init(version: Int = SpaceJuggler.version, linger: TimeInterval = 60) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sj-\(UUID().uuidString.prefix(8))")
            place = BrokerPlace(directory: directory)
            broker = Broker(version: version, place: place, linger: linger, usesDevices: false,
                            settings: UserDefaults(suiteName: "me.metaebene.SpaceJuggler.tests.\(UUID())")!,
                            record: .init(version: version, path: "/usr/bin/true"))
            broker.onLeave = { [weak self] in self?.left = true }
            broker.log = { [weak self] in self?.log.append($0) }
            guard case .elected(let lockFile) = Election.run(place: place, version: version, log: { _ in }) else {
                fatalError("not elected in \(directory.path)")
            }
            broker.start(lockFile: lockFile)
        }

        func client(_ name: String, _ claim: Claim?) -> Recorder {
            let recorder = Recorder()
            let client = SpaceJugglerConnection(name: name, claim: claim ?? Claim(apps: []), launcher: .none, place: place)
            client.onEvent = { recorder.events.append($0) }
            client.start()
            clients.append(client)
            return recorder
        }

        func stopClient(_ index: Int) {
            clients[index].stop()
        }

        /// Asks as a newer broker would (hello, takeOver), and returns the answers until `handingOver`.
        func takeOver(version: Int) async -> [BrokerMessage] {
            let fd = UnixSocket.connect(to: place.socket.path)!
            let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
            var answers: [BrokerMessage] = []
            var done = false
            connection.onMessage = { answers.append($0); if case .handingOver = $0 { done = true } }
            connection.onClose = { done = true }
            connection.start()
            connection.send(.hello(Hello(version: version, processID: getpid(), name: "test v\(version)", claim: nil)))
            connection.send(.takeOver(version: version))
            await until { done }
            connection.close()
            return answers
        }

        /// Stops the clients and makes the broker hand over, so that nothing of it stays on the main queue.
        func finish() async {
            for client in clients { client.stop() }
            if !left { _ = await takeOver(version: broker.version + 1) }
            try? FileManager.default.removeItem(at: place.directory)
        }
    }

    /// Lets the main queue turn until `condition` holds, or two seconds passed.
    static func until(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aBackgroundClaimGetsTheInputOnceTheBrokerSettled() async {
        let harness = Harness()
        let stagehand = harness.client("Stagehand", Claim(apps: [], background: true))
        await Self.until { stagehand.holds == true }
        #expect(stagehand.connected)
        #expect(stagehand.holds == true)
        #expect(harness.broker.status.clients.map(\.holds) == [true])
        await harness.finish()
        #expect(harness.left)
        #expect(stagehand.events.contains(.disconnected))
    }

    @Test func theEarlierBackgroundClaimKeepsItAndTheNextOneFollows() async {
        let harness = Harness()
        let first = harness.client("First", Claim(apps: [], background: true))
        await Self.until { first.holds == true }
        let second = harness.client("Second", Claim(apps: [], background: true))
        await Self.until { second.connected }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(first.holds == true)
        #expect(second.holds == nil, "nobody listens in")
        harness.stopClient(0)
        await Self.until { second.holds == true }
        #expect(second.holds == true)
        #expect(harness.broker.status.clients.map(\.name) == ["Second"])
        await harness.finish()
    }

    @Test func backgroundLastComesAfterEveryOtherBackgroundClaim() async {
        let harness = Harness()
        let stagehand = harness.client("Stagehand", Claim(apps: [], background: true, backgroundLast: true))
        await Self.until { stagehand.holds == true }
        let kugelblitz = harness.client("Kugelblitz", Claim(apps: [], background: true))
        // Two sockets: either client may read its news first.
        await Self.until { kugelblitz.holds == true && stagehand.holds == false }
        #expect(kugelblitz.holds == true)
        #expect(stagehand.holds == false, "told that it lost the input")
        await harness.finish()
    }

    @Test func aClaimForAnAppNotInFrontWaits() async {
        let harness = Harness()
        let shuttle = harness.client("Space Shuttle", Claim(apps: ["com.example.nobody"]))
        await Self.until { shuttle.connected }
        try? await Task.sleep(for: .milliseconds(400))
        #expect(shuttle.holds == nil)
        #expect(harness.broker.status.clients.map(\.holds) == [false])
        await harness.finish()
    }

    @Test func statusAnswersAnyConnection() async {
        let harness = Harness()
        let stagehand = harness.client("Stagehand", Claim(apps: [], background: true))
        // Its hello must be in before the status is asked on another socket.
        await Self.until { stagehand.connected }
        let fd = UnixSocket.connect(to: harness.place.socket.path)!
        let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
        var status: BrokerStatus?
        connection.onMessage = { if case .status(let answer) = $0 { status = answer } }
        connection.start()
        connection.send(.hello(Hello(version: SpaceJuggler.version, processID: getpid(), name: "cli", claim: nil)))
        connection.send(.status)
        await Self.until { status != nil }
        #expect(status?.version == SpaceJuggler.version)
        #expect(status?.processID == getpid())
        #expect(status?.clients.map(\.name) == ["Stagehand"], "a connection without a claim is no client")
        #expect(status?.driver == false)
        connection.close()
        await harness.finish()
    }

    @Test func onlyANewerBrokerIsHandedOverTo() async {
        let harness = Harness(version: 5)
        let same = await harness.takeOver(version: 5)
        #expect(same.contains(.handingOver(false)))
        #expect(same.contains(.welcome(version: 5, protocolVersion: SpaceJuggler.protocolVersion)))
        #expect(!harness.left)
        let newer = await harness.takeOver(version: 6)
        #expect(newer.contains(.handingOver(true)))
        #expect(harness.left)
        await harness.finish()
    }

    @Test func withoutClaimsTheBrokerLeavesAfterLingering() async {
        let harness = Harness(linger: 0.2)
        await Self.until { harness.left }
        #expect(harness.left)
        #expect(harness.log.contains { $0.hasPrefix("no clients for") })
        #expect(!FileManager.default.fileExists(atPath: harness.place.socket.path), "the socket file goes with it")
        await harness.finish()
    }

    @Test func aClaimCancelsTheLingering() async {
        let harness = Harness(linger: 0.3)
        let stagehand = harness.client("Stagehand", Claim(apps: [], background: true))
        await Self.until { stagehand.holds == true }
        try? await Task.sleep(for: .milliseconds(400))
        #expect(!harness.left)
        await harness.finish()
    }
}

/// `Election.run` without a broker to talk to.
struct ElectionTests {
    private func place() -> BrokerPlace {
        BrokerPlace(directory: FileManager.default.temporaryDirectory.appendingPathComponent("sj-\(UUID().uuidString.prefix(8))"))
    }

    @Test func electedWhenTheLockIsFree() {
        let place = place()
        defer { try? FileManager.default.removeItem(at: place.directory) }
        guard case .elected(let lockFile) = Election.run(place: place, version: 1, log: { _ in }) else {
            Issue.record("not elected")
            return
        }
        // The directory is the user's alone (ADR-0009).
        let permissions = (try? FileManager.default.attributesOfItem(atPath: place.directory.path))?[.posixPermissions] as? Int
        #expect(permissions == 0o700)
        close(lockFile)
    }

    @Test(.timeLimit(.minutes(1))) func aLockHeldByNobodyWhoAnswersFails() {
        let place = place()
        defer { try? FileManager.default.removeItem(at: place.directory) }
        place.ensureDirectory()
        let holder = open(place.lock.path, O_CREAT | O_RDWR, 0o600)
        #expect(flock(holder, LOCK_EX | LOCK_NB) == 0)
        defer { close(holder) }
        // About two seconds: twenty attempts to connect to a socket nobody listens at.
        #expect(Election.run(place: place, version: 1, log: { _ in }) == .failed("lock held, but no broker answers"))
    }
}
