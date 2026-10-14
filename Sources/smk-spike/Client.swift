import Foundation
import SpaceMouseBroker

/// A client as an app would be one: connects to the broker, starts one if there is none (the newest known), claims,
/// prints what it gets, reconnects when the broker goes away (ADR-0001).
@MainActor
final class Client {
    private let name: String
    private let claim: Claim
    private let version: Int
    private let place: BrokerPlace
    private let quiet: Bool
    private var connection: LineConnection<ClientMessage, BrokerMessage>?
    private var axesCount = 0

    init(name: String, claim: Claim, version: Int, place: BrokerPlace, quiet: Bool) {
        self.name = name
        self.claim = claim
        self.version = version
        self.place = place
        self.quiet = quiet
    }

    func start() { connect(attempt: 0) }

    /// Tries for a moment before starting a broker (one may be handing over), then starts one and keeps trying.
    private func connect(attempt: Int) {
        if let fd = UnixSocket.connect(to: place.socket.path) {
            let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
            connection.onMessage = { [weak self] in self?.received($0) }
            connection.onClose = { [weak self] in
                guard let self else { return }
                say("[\(name)] broker gone")
                self.connection = nil
                self.connect(attempt: 0)
            }
            self.connection = connection
            connection.start()
            connection.send(.hello(protocolVersion: Wire.protocolVersion, processID: getpid(), name: name, claim: claim))
            return
        }
        if attempt == 5 { launchBroker() }
        guard attempt < 40 else {
            say("[\(name)] no broker after \(attempt) attempts")
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.connect(attempt: attempt + 1) }
    }

    /// Its own broker, or the newest one recorded if that is newer and still there. In an app this would open the
    /// helper app in the bundle; here it is this tool, detached in its own session.
    private func launchBroker() {
        var path = executablePath
        var brokerVersion = version
        if let newest = place.readNewest(), newest.version > version, FileManager.default.isExecutableFile(atPath: newest.path) {
            path = newest.path
            brokerVersion = newest.version
        }
        say("[\(name)] starting broker v\(brokerVersion)")
        let log = place.directory.appendingPathComponent("broker.log").path
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        let arguments = [path, "broker", "--version", String(brokerVersion)]
        var argv = arguments.map { strdup($0) } + [nil]
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attributes, &argv, environ)
        argv.forEach { free($0) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attributes)
        if result != 0 { say("[\(name)] could not start broker (\(result))") }
    }

    private func received(_ message: BrokerMessage) {
        switch message {
        case .welcome(let brokerVersion, _):
            say("[\(name)] connected to broker v\(brokerVersion)")
            // This client brings a newer broker: start it, it takes over (ADR-0001, newest wins).
            if brokerVersion < version { launchBroker() }
        case .holding(let holds): say("[\(name)] \(holds ? "HOLDS the SpaceMouse" : "lost the SpaceMouse")")
        case .axes(let device, let x, let y, let z, let rx, let ry, let rz):
            axesCount += 1
            if !quiet, axesCount % 10 == 1 { say("[\(name)] \(device) x \(x) y \(y) z \(z) rx \(rx) ry \(ry) rz \(rz)") }
        case .buttons(let device, let held): say("[\(name)] \(device) buttons \(held)")
        case .status, .handingOver: break
        }
    }
}
