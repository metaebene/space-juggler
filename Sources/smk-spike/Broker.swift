import AppKit
import Foundation
import SpaceMouseBroker
import SpaceMouseKit

/// The broker: owns every SpaceMouse and hands it to exactly one client (ADR-0001).
@MainActor
final class Broker {
    private struct Client {
        let connection: LineConnection<BrokerMessage, ClientMessage>
        var name = "?"
        var claimant: Claimant?
    }

    private let version: Int
    private let place: BrokerPlace
    private let linger: TimeInterval
    private let usesDevices: Bool
    private let lockFD: Int32
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int: Client] = [:]
    private var nextID = 1
    private var arbitrations = 0
    private var holder: Int?
    private var lingerWork: DispatchWorkItem?
    /// Set while handing over: closing connections must not reopen the devices.
    private var leaving = false
    private let devices = Devices()

    init(version: Int, place: BrokerPlace, linger: TimeInterval, usesDevices: Bool, lockFD: Int32) {
        self.version = version
        self.place = place
        self.linger = linger
        self.usesDevices = usesDevices
        self.lockFD = lockFD
    }

    /// Takes the lock, or asks the running broker to hand over if this one is newer. Returns the locked file, or nil
    /// if the running broker stays.
    static func acquireLock(place: BrokerPlace, version: Int) -> Int32? {
        try? FileManager.default.createDirectory(at: place.directory, withIntermediateDirectories: true)
        let fd = open(place.lock.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
        // Held: the running broker answers on the socket (retry while it is still starting up).
        var answer: (running: Int, leaves: Bool)?
        for _ in 0..<20 where answer == nil {
            answer = askToHandOver(place: place, version: version)
            if answer == nil { usleep(100_000) }
        }
        guard let answer else {
            say("lock held, but no broker answers")
            close(fd)
            return nil
        }
        guard answer.leaves else {
            say("running broker v\(answer.running) stays (this is v\(version))")
            close(fd)
            return nil
        }
        say("running broker v\(answer.running) hands over to v\(version)")
        let started = Date()
        while Date().timeIntervalSince(started) < 5 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                say("lock taken after \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                return fd
            }
            usleep(20_000)
        }
        say("old broker did not let go of the lock")
        close(fd)
        return nil
    }

    /// Synchronous: hello + takeOver, wait for welcome and the answer.
    private static func askToHandOver(place: BrokerPlace, version: Int) -> (running: Int, leaves: Bool)? {
        guard let fd = UnixSocket.connect(to: place.socket.path) else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        for message in [ClientMessage.hello(protocolVersion: Wire.protocolVersion, processID: getpid(),
                                            name: "broker v\(version)", claim: nil), .takeOver(version: version)] {
            let data = LineEncoder.encode(message)
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
        var decoder = LineDecoder<BrokerMessage>()
        var running: Int?
        var buffer = [UInt8](repeating: 0, count: 4096)
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

    func start() {
        place.recordNewest(.init(version: version, path: executablePath))
        guard let fd = UnixSocket.listen(at: place.socket.path) else {
            say("cannot listen at \(place.socket.path)")
            exit(1)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept() } }
        acceptSource = source
        source.resume()
        say("broker v\(version) (pid \(getpid())) listening")

        devices.log = { say($0) }
        devices.onAxes = { [weak self] device, axes in
            guard let self, let holder, let client = clients[holder] else { return }
            client.connection.send(.axes(device: device, x: axes.x, y: axes.y, z: axes.z, rx: axes.rx, ry: axes.ry, rz: axes.rz))
        }
        devices.onButtons = { [weak self] device, buttons in
            guard let self, let holder, let client = clients[holder] else { return }
            client.connection.send(.buttons(device: device, held: buttons.names))
        }
        if usesDevices { devices.start() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundle = app?.bundleIdentifier
            MainActor.assumeIsolated {
                say("frontmost: \(bundle ?? "?")")
                self?.arbitrate()
            }
        }
        scheduleLingerIfIdle()
    }

    private func accept() {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        let id = nextID
        nextID += 1
        let connection = LineConnection<BrokerMessage, ClientMessage>(fd: fd)
        connection.onMessage = { [weak self] in self?.received($0, from: id) }
        connection.onClose = { [weak self] in self?.closed(id) }
        clients[id] = Client(connection: connection)
        connection.start()
    }

    private func received(_ message: ClientMessage, from id: Int) {
        guard let connection = clients[id]?.connection else { return }
        switch message {
        case .hello(let protocolVersion, let processID, let name, let claim):
            clients[id]?.name = name
            connection.send(.welcome(brokerVersion: version, protocolVersion: Wire.protocolVersion))
            if protocolVersion != Wire.protocolVersion { say("\(name) speaks protocol \(protocolVersion)") }
            if let claim {
                clients[id]?.claimant = Claimant(id: id, processID: processID, claim: claim, connected: id)
                say("client \(name) (pid \(processID)) claims \(Self.describe(claim))")
                lingerWork?.cancel()
                arbitrate()
            }
        case .claim(let claim):
            clients[id]?.claimant?.claim = claim
            arbitrate()
        case .status:
            connection.send(.status(status))
        case .takeOver(let candidate):
            let leaves = candidate > version
            connection.send(.handingOver(leaves))
            if leaves { handOver(to: candidate) }
        }
    }

    private func closed(_ id: Int) {
        guard !leaving, let client = clients.removeValue(forKey: id) else { return }
        if client.claimant != nil { say("client \(client.name) left") }
        arbitrate()
        scheduleLingerIfIdle()
    }

    private var frontmost: (app: String?, process: Int32?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.processIdentifier)
    }

    private func arbitrate() {
        arbitrations += 1
        let claimants = clients.values.compactMap(\.claimant)
        let front = frontmost
        let decision = Arbiter.decide(claimants, frontmostApp: front.app, frontmostProcess: front.process)
        if decision.throughFront, let id = decision.holder { clients[id]?.claimant?.lastFrontUse = arbitrations }
        devices.want(decision.holder != nil)
        guard decision.holder != holder else { return }
        if let old = holder { clients[old]?.connection.send(.holding(false)) }
        holder = decision.holder
        if let new = holder { clients[new]?.connection.send(.holding(true)) }
        let name = holder.flatMap { clients[$0]?.name } ?? "nobody"
        say("holder: \(name)\(holder == nil ? "" : decision.throughFront ? " (front: \(front.app ?? "?"))" : " (background)")")
    }

    /// A newer broker takes over: let go of the devices first, then leave; the lock goes with the process.
    private func handOver(to candidate: Int) {
        say("handing over to v\(candidate)")
        leaving = true
        devices.stop()
        acceptSource?.cancel()
        Darwin.close(listenFD)
        // Clients see the connection close and reconnect to the new broker.
        for client in clients.values { client.connection.close() }
        exit(0)
    }

    private func scheduleLingerIfIdle() {
        guard !clients.values.contains(where: { $0.claimant != nil }) else { return }
        lingerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.clients.values.contains(where: { $0.claimant != nil }) else { return }
                say("no clients for \(Int(self.linger)) s, leaving")
                self.devices.stop()
                unlink(self.place.socket.path)
                exit(0)
            }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + linger, execute: work)
    }

    private var status: BrokerStatus {
        BrokerStatus(
            brokerVersion: version, processID: getpid(), frontmostApp: frontmost.app,
            devices: devices.list.map { .init(id: $0.id, model: $0.model, state: $0.state) },
            clients: clients.compactMap { id, client in
                client.claimant.map { .init(id: id, name: client.name, processID: $0.processID, claim: $0.claim, holds: id == holder) }
            }.sorted { $0.id < $1.id })
    }

    static func describe(_ claim: Claim) -> String {
        let apps = claim.apps.isEmpty ? "no app" : claim.apps.joined(separator: ", ")
        return apps + (claim.background ? " + background" : "")
    }
}

extension SpaceMouseButtons {
    static let named: [(SpaceMouseButtons, String)] = [
        (.left, "left"), (.right, "right"), (.key1, "1"), (.key2, "2"), (.key3, "3"), (.key4, "4"), (.menu, "menu"),
        (.fit, "fit"), (.viewTop, "T"), (.viewRight, "R"), (.viewFront, "F"), (.viewRoll, "roll"), (.escape, "esc"),
        (.shift, "shift"), (.control, "ctrl"), (.alt, "alt"), (.rotationLock, "rotation lock"),
    ]

    var names: [String] { Self.named.filter { contains($0.0) }.map(\.1) }
}
