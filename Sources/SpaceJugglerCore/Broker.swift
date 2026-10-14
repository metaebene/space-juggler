import AppKit
import Foundation
import SpaceJugglerProtocol

/// Space Juggler's broker: owns every SpaceMouse and gives the input to exactly one client (ADR-0001). Runs on the
/// main queue of the process that won the election (`Election`).
@MainActor
public final class Broker {
    private struct Client {
        let connection: LineConnection<BrokerMessage, ClientMessage>
        var name = "?"
        var greeted = false
        var claimant: Claimant?
    }

    public let version: Int
    private let place: BrokerPlace
    private let linger: TimeInterval
    private let usesDevices: Bool
    private let settings: UserDefaults
    private let record: BrokerPlace.Newest
    private var lockFile: Int32 = -1
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int: Client] = [:]
    private var nextID = 1
    private var arbitrations = 0
    private var holder: Int?
    private var lingerWork: DispatchWorkItem?
    /// Set while leaving: closing connections must not reopen the devices.
    private var leaving = false
    private let devices = Devices()
    private var startedAt = Date()
    private var settlePending = false
    private static let settleTime: TimeInterval = 0.3
    private var observer: NSObjectProtocol?

    /// Something the menu shows changed: devices, clients, holder.
    public var onChange: () -> Void = {}
    /// The broker is done (handed over or idle); the app terminates, the CLI exits.
    public var onLeave: () -> Void = { exit(0) }
    public var log: (String) -> Void = { _ in }

    /// `record` is how a client starts this broker again (newest wins, ADR-0001).
    public init(version: Int = SpaceJuggler.version, place: BrokerPlace = .standard, linger: TimeInterval = 10,
                usesDevices: Bool = true, settings: UserDefaults = .standard, record: BrokerPlace.Newest) {
        self.version = version
        self.place = place
        self.linger = linger
        self.usesDevices = usesDevices
        self.settings = settings
        self.record = record
    }

    /// Starts serving; `lockFile` comes from `Election` and stays open while the broker runs.
    public func start(lockFile: Int32) {
        self.lockFile = lockFile
        startedAt = Date()
        place.rotateLog()
        place.recordNewest(record)
        guard let fd = UnixSocket.listen(at: place.socket.path) else {
            say("cannot listen at \(place.socket.path)")
            return onLeave()
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.accept() } }
        acceptSource = source
        source.resume()
        say("Space Juggler v\(version) (pid \(getpid())) listening")

        devices.log = { [weak self] in self?.say($0) }
        devices.isEnabled = { [weak self] in self?.isEnabled($0) ?? true }
        devices.onAxes = { [weak self] device, axes in self?.toHolder(.axes(device: device, axes: axes)) }
        devices.onButtons = { [weak self] device, held in self?.toHolder(.buttons(device: device, held: held)) }
        devices.onChange = { [weak self] in
            guard let self else { return }
            let list = devices.list
            for client in clients.values where client.greeted { client.connection.send(.devices(list)) }
            onChange()
        }
        if usesDevices { devices.start() }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.arbitrate() } }
        scheduleLingerIfIdle()
    }

    // MARK: - For the menu

    public var status: BrokerStatus {
        BrokerStatus(
            version: version, processID: getpid(), frontmostApp: frontmost.app, devices: devices.list,
            clients: clients.compactMap { id, client in
                client.claimant.map { .init(id: id, name: client.name, processID: $0.processID, claim: $0.claim, holds: id == holder) }
            }.sorted { $0.id < $1.id })
    }

    public func isEnabled(_ device: String) -> Bool {
        !(settings.stringArray(forKey: "disabledDevices") ?? []).contains(device)
    }

    /// Turns a device on or off in the menu, by its identity (ADR-0003). Off: its buttons are let go for the holder.
    public func setEnabled(_ enabled: Bool, device: String) {
        var disabled = Set(settings.stringArray(forKey: "disabledDevices") ?? [])
        if enabled { disabled.remove(device) } else { disabled.insert(device) }
        settings.set(disabled.sorted(), forKey: "disabledDevices")
        if !enabled {
            toHolder(.axes(device: device, axes: .zero))
            toHolder(.buttons(device: device, held: []))
        }
        devices.onChange()
    }

    // MARK: - Clients

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
        case .hello(let hello):
            clients[id]?.name = hello.name
            clients[id]?.greeted = true
            connection.send(.welcome(version: version, protocolVersion: SpaceJuggler.protocolVersion))
            connection.send(.devices(devices.list))
            if hello.protocolVersion != SpaceJuggler.protocolVersion { say("\(hello.name) speaks protocol \(hello.protocolVersion)") }
            if let claim = hello.claim {
                clients[id]?.claimant = Claimant(id: id, processID: hello.processID, claim: claim, connected: id)
                say("\(hello.name) (pid \(hello.processID), v\(hello.version)) claims \(Self.describe(claim))")
                lingerWork?.cancel()
                arbitrate()
                onChange()
            }
        case .claim(let claim):
            clients[id]?.claimant?.claim = claim
            say("\(clients[id]?.name ?? "?") claims \(Self.describe(claim))")
            arbitrate()
            onChange()
        case .setLED(let device, let on):
            if let failure = devices.setLED(on, device: device) { say("LED \(device) for \(clients[id]?.name ?? "?"): \(failure)") }
        case .status:
            connection.send(.status(status))
        case .takeOver(let candidate):
            let leaves = candidate > version
            connection.send(.handingOver(leaves))
            if leaves { leave(because: "handing over to v\(candidate)") }
        }
    }

    private func closed(_ id: Int) {
        guard !leaving, let client = clients.removeValue(forKey: id) else { return }
        if client.claimant != nil {
            say("\(client.name) left")
            arbitrate()
            onChange()
        }
        scheduleLingerIfIdle()
    }

    private func toHolder(_ message: BrokerMessage) {
        guard let holder, let client = clients[holder] else { return }
        client.connection.send(message)
    }

    // MARK: - Arbitration

    private var frontmost: (app: String?, process: Int32?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.processIdentifier)
    }

    private func arbitrate() {
        guard !leaving else { return }
        // Right after starting (a handover, a restart) the clients reconnect one by one within ~100 ms: decide once
        // they are back, instead of handing the input to whoever came first.
        let settling = Self.settleTime - Date().timeIntervalSince(startedAt)
        if settling > 0 {
            guard !settlePending else { return }
            settlePending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + settling) { [weak self] in
                MainActor.assumeIsolated {
                    self?.settlePending = false
                    self?.arbitrate()
                }
            }
            return
        }
        arbitrations += 1
        let front = frontmost
        let decision = Arbiter.decide(clients.values.compactMap(\.claimant), frontmostApp: front.app, frontmostProcess: front.process)
        if decision.throughFront, let id = decision.holder { clients[id]?.claimant?.lastFrontUse = arbitrations }
        devices.want(decision.holder != nil)
        guard decision.holder != holder else { return }
        if let old = holder { clients[old]?.connection.send(.holding(false)) }
        holder = decision.holder
        if let new = holder { clients[new]?.connection.send(.holding(true)) }
        let name = holder.flatMap { clients[$0]?.name } ?? "nobody"
        say("holder: \(name)\(holder == nil ? "" : decision.throughFront ? " (front: \(front.app ?? "?"))" : " (background)")")
        onChange()
    }

    // MARK: - Leaving

    /// Let go of the devices first, then leave; the lock goes with the process.
    private func leave(because reason: String) {
        say(reason)
        leaving = true
        devices.stop()
        acceptSource?.cancel()
        Darwin.close(listenFD)
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for client in clients.values { client.connection.close() }
        onLeave()
    }

    private func scheduleLingerIfIdle() {
        guard !clients.values.contains(where: { $0.claimant != nil }) else { return }
        lingerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.leaving, !self.clients.values.contains(where: { $0.claimant != nil }) else { return }
                // Still holding the lock: the socket file is ours to remove.
                unlink(self.place.socket.path)
                self.leave(because: "no clients for \(Int(self.linger)) s, leaving")
            }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + linger, execute: work)
    }

    private func say(_ text: String) {
        log(text)
        place.appendLog(text)
    }

    static func describe(_ claim: Claim) -> String {
        let apps = claim.apps.isEmpty ? "no app" : claim.apps.joined(separator: ", ")
        return apps + (claim.background ? " + background" : "")
    }
}
