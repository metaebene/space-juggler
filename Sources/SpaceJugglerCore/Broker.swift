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
        var protocolVersion = 1
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
    private var observers: [NSObjectProtocol] = []
    private var helperWatch: NSKeyValueObservation?
    /// 3Dconnexion's helper runs and holds the SpaceMice: Space Juggler goes through the driver (ADR-0004).
    private var driverMode = false
    private let driver = DriverClient()

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
        devices.onReport = { [weak self] device, bytes in self?.toHolder(.report(device: device, bytes: bytes)) }
        devices.wantsReports = { [weak self] in self?.holderWantsReports ?? false }
        devices.onChange = { [weak self] in
            guard let self else { return }
            let list = devices.list
            for client in clients.values where client.greeted { client.connection.send(.devices(list)) }
            onChange()
        }
        driver.log = { [weak self] in self?.say($0) }
        driver.onAxes = { [weak self] axes in
            guard let self, let device = driverDevice else { return }
            toHolder(.axes(device: device.id, axes: axes))
        }
        driver.onButtons = { [weak self] bits in
            guard let self, let device = driverDevice else { return }
            // The driver's bitmap in the device's numbering, named by the model of the device it is put down to.
            let held = devices.model(of: device.id)?.buttons(UInt64(bits)) ?? []
            toHolder(.buttons(device: device.id, held: held))
        }
        if usesDevices {
            updateDriverMode()
            devices.start()
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.arbitrate() }
        })
        // The helper comes and goes (login, its own updates, quit by the user). It is an `LSUIElement` app, for which
        // NSWorkspace posts neither didLaunch nor didTerminate (quitting it went unnoticed, 2026-10-15); the list of
        // running apps covers every app and changes on the main run loop.
        helperWatch = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateDriverMode() }
        }
        scheduleLingerIfIdle()
    }

    // MARK: - For the menu

    public var status: BrokerStatus {
        var status = BrokerStatus(
            version: version, processID: getpid(), frontmostApp: frontmost.app, devices: devices.list,
            clients: clients.compactMap { id, client in
                client.claimant.map { .init(id: id, name: client.name, processID: $0.processID, claim: $0.claim, holds: id == holder) }
            }.sorted { $0.id < $1.id })
        status.driver = driverMode
        return status
    }

    /// The device the driver's input is put down to: the driver merges every SpaceMouse and does not say which one
    /// moved, so the first one that is on (ADR-0004).
    private var driverDevice: SpaceMouseDevice? { devices.list.first { $0.enabled } }

    /// Through the driver while its helper runs, seized otherwise (ADR-0004). Never kills or starts the helper.
    private func updateDriverMode() {
        let runs = DriverClient.helperRuns
        guard runs != driverMode else { return }
        driverMode = runs
        devices.driverHolds = runs
        say(runs ? "3Dconnexion helper runs: through the driver" : "3Dconnexion helper gone: seizing again")
        if runs {
            devices.want(false)
            driver.start()
        } else {
            driver.stop()
        }
        arbitrate()
        devices.onChange()
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
            clients[id]?.protocolVersion = hello.protocolVersion
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
            if driverMode {
                // Through the driver ('3dsl'); the Compact ignores it (stagehand findings).
                driver.setLED(on)
            } else if let failure = devices.setLED(on, device: device) {
                say("LED \(device) for \(clients[id]?.name ?? "?"): \(failure)")
            }
        case .describe(let device):
            devices.describe(device) { [weak self] description in
                self?.clients[id]?.connection.send(.description(description))
            }
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
        if client.connection.stalled { say("\(client.name) stopped reading: dropped") }
        if client.claimant != nil {
            say("\(client.name) left")
            arbitrate()
            onChange()
        }
        scheduleLingerIfIdle()
    }

    private func toHolder(_ message: BrokerMessage) {
        guard let holder, let client = clients[holder] else { return }
        switch message {
        case .buttons(let device, let held) where client.protocolVersion < 2:
            // Protocol 1 reads the button set as a UInt32 (ADR-0005).
            client.connection.send(.buttons(device: device, held: held.intersection(.protocol1)))
        case .report where client.claimant?.claim.raw != true:
            break
        default:
            client.connection.send(message)
        }
    }

    /// The holder asked for raw input reports (a probe, ADR-0006).
    private var holderWantsReports: Bool {
        holder.flatMap { clients[$0]?.claimant?.claim.raw } ?? false
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
        var claimants = clients.values.compactMap(\.claimant)
        // Through the driver only claims for the frontmost app count: in the background Space Juggler would take the
        // driver's data from every other app in front, including those with their own support (ADR-0004).
        if driverMode { claimants = claimants.map { var c = $0; c.claim.background = false; return c } }
        let decision = Arbiter.decide(claimants, frontmostApp: front.app, frontmostProcess: front.process)
        if decision.throughFront, let id = decision.holder { clients[id]?.claimant?.lastFrontUse = arbitrations }
        devices.want(decision.holder != nil && !driverMode)
        driver.want(decision.holder != nil && driverMode)
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
        driver.stop()
        acceptSource?.cancel()
        Darwin.close(listenFD)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        helperWatch = nil
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
