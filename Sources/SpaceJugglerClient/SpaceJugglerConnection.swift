import AppKit
import Foundation
import IOKit.hid
@_exported import SpaceJugglerProtocol

/// What an app links to get the SpaceMouse (ADR-0001, ADR-0002): connects to Space Juggler, starts it when nobody
/// answers (the newest one known, else the app's own), starts its own when it meets an older one, reconnects when it
/// goes away, and sends the app's claim. Main actor only.
@MainActor
public final class SpaceJugglerConnection {
    /// How this client starts a broker of its own.
    public enum Launcher: Sendable {
        /// `Space Juggler.app` inside the app, opened through Launch Services (ADR-0002).
        case app(URL)
        /// A command-line tool and its arguments, spawned (tests and the CLI only; ADR-0002 forbids this for apps).
        case executable(path: String, arguments: [String])
        /// Never starts one; only connects.
        case none

        /// `Contents/Helpers/Space Juggler.app` of the main bundle.
        public static var bundled: Launcher {
            .app(Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(SpaceJuggler.appName).app"))
        }
    }

    public enum Event: Sendable, Equatable {
        /// Connected to a broker of this version.
        case connected(version: Int)
        /// The broker went away; the connection tries again by itself. `holding(false)` came before it if needed.
        case disconnected
        /// This app gets the input (true) or no longer (false). On false, axes and buttons have been reset already.
        case holding(Bool)
        case devices([SpaceMouseDevice])
        case axes(SpaceMouseAxes, device: String)
        /// The buttons held on `device`; `heldButtons` has them for all devices together.
        case buttons(SpaceMouseButtons, device: String)
        /// No broker could be reached or started for a while; the connection keeps trying.
        case unavailable(String)
    }

    public var onEvent: (Event) -> Void = { _ in }
    public private(set) var devices: [SpaceMouseDevice] = []
    public private(set) var holds = false
    public private(set) var brokerVersion: Int?

    private let name: String
    private var claim: Claim
    private let launcher: Launcher
    private let place: BrokerPlace
    private let version: Int
    private var connection: LineConnection<ClientMessage, BrokerMessage>?
    private var running = false
    private var attempt = 0
    private var lastLaunch: Date?
    private var held: [String: SpaceMouseButtons] = [:]
    private var moved: Set<String> = []

    public init(name: String, claim: Claim, launcher: Launcher = .bundled, place: BrokerPlace = .standard,
                version: Int = SpaceJuggler.version) {
        self.name = name
        self.claim = claim
        self.launcher = launcher
        self.place = place
        self.version = version
    }

    /// Whether a SpaceMouse of a known model is attached (cable, receiver or Bluetooth), from the I/O Registry alone,
    /// without Space Juggler and without opening anything: without one, a failure to reach Space Juggler is nothing to
    /// tell the user about (Kugelblitz ADR-0226).
    public nonisolated static var isSpaceMouseAttached: Bool {
        SpaceMouseModel.known.contains { model in
            let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
            matching[kIOHIDVendorIDKey] = model.vendorID
            matching[kIOHIDProductIDKey] = model.productID
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return false }
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return false }
            IOObjectRelease(service)
            return true
        }
    }

    /// The buttons held on all devices together (several SpaceMice act as one, ADR-0003).
    public var heldButtons: SpaceMouseButtons { held.values.reduce([]) { $0.union($1) } }

    /// The same for a program that only knows two buttons, `.left` and `.right`: the Compact's two, the Pro's MENU and
    /// FIT (`SpaceMouseModel.twoButtons`).
    public var heldTwoButtons: SpaceMouseButtons {
        held.reduce([]) { result, entry in
            guard let model = devices.first(where: { $0.id == entry.key })?.model else { return result }
            return result.union(model.asTwoButtons(entry.value))
        }
    }

    /// Switches the LED of every device that has one (and can light it now).
    public func setLEDs(_ on: Bool) {
        for device in devices where device.model?.hasStatusLED == true && !(device.model!.statusLEDNeedsCable && device.isBluetooth) {
            setLED(on, device: device.id)
        }
    }

    public func start() {
        guard !running else { return }
        running = true
        attempt = 0
        connect()
    }

    public func stop() {
        running = false
        connection?.close()
        connection = nil
    }

    /// Sends a new claim (Space Glider when the apps turned on change; Kugelblitz when "keep in background" changes).
    public func setClaim(_ claim: Claim) {
        self.claim = claim
        connection?.send(.claim(claim))
    }

    public func setLED(_ on: Bool, device: String) {
        connection?.send(.setLED(device: device, on: on))
    }

    // MARK: - Connecting

    private func connect() {
        guard running, connection == nil else { return }
        if let fd = UnixSocket.connect(to: place.socket.path) {
            attempt = 0
            let connection = LineConnection<ClientMessage, BrokerMessage>(fd: fd)
            connection.onMessage = { [weak self] in self?.received($0) }
            connection.onClose = { [weak self] in self?.lost() }
            self.connection = connection
            connection.start()
            connection.send(.hello(Hello(version: version, processID: getpid(), name: name, claim: claim)))
            return
        }
        attempt += 1
        // Wait half a second first: a broker may be handing over to a newer one.
        if attempt == 5 { launch() }
        if attempt == 50 { onEvent(.unavailable("Space Juggler could not be reached")) }
        let delay = attempt < 50 ? 0.1 : 2
        if attempt >= 50, attempt % 15 == 0 { launch() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.connect() }
        }
    }

    private func lost() {
        connection = nil
        brokerVersion = nil
        if holds { setHolds(false) }
        onEvent(.disconnected)
        guard running else { return }
        attempt = 0
        connect()
    }

    /// Starts the newest broker known if it is newer than this client's, else this client's own. Not more than once
    /// in 3 s.
    private func launch() {
        if let lastLaunch, Date().timeIntervalSince(lastLaunch) < 3 { return }
        lastLaunch = Date()
        if let newest = place.readNewest(), newest.version > version, newest.exists {
            return Self.start(newest.isApp ? .app(URL(fileURLWithPath: newest.path)) : .executable(path: newest.path, arguments: newest.arguments))
        }
        Self.start(launcher)
    }

    private static func start(_ launcher: Launcher) {
        switch launcher {
        case .app(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            // Another copy (older, same bundle ID) may be running: this one must start anyway to take over.
            configuration.createsNewApplicationInstance = true
            configuration.promptsUserIfNeeded = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        case .executable(let path, let arguments):
            spawnDetached(path: path, arguments: arguments)
        case .none:
            break
        }
    }

    private static func spawnDetached(path: String, arguments: [String]) {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var argv = ([path] + arguments).map { strdup($0) } + [nil]
        var pid: pid_t = 0
        posix_spawn(&pid, path, &actions, &attributes, &argv, environ)
        argv.forEach { free($0) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attributes)
    }

    // MARK: - Messages

    private func received(_ message: BrokerMessage) {
        switch message {
        case .welcome(let brokerVersion, _):
            self.brokerVersion = brokerVersion
            onEvent(.connected(version: brokerVersion))
            // This client brings a newer broker: start it, it takes over (ADR-0001).
            if brokerVersion < version { Self.start(launcher) }
        case .devices(let list):
            devices = list
            onEvent(.devices(list))
        case .holding(let holds):
            setHolds(holds)
        case .axes(let device, let axes):
            guard holds else { return }
            if axes.isZero { moved.remove(device) } else { moved.insert(device) }
            onEvent(.axes(axes, device: device))
        case .buttons(let device, let buttons):
            guard holds else { return }
            held[device] = buttons.isEmpty ? nil : buttons
            onEvent(.buttons(buttons, device: device))
        case .status, .handingOver:
            break
        }
    }

    /// Losing the input lets go of everything the app still thinks is held.
    private func setHolds(_ holds: Bool) {
        if !holds {
            let (moved, held) = (self.moved, self.held)
            self.moved = []
            self.held = [:]
            for device in moved { onEvent(.axes(.zero, device: device)) }
            for device in held.keys { onEvent(.buttons([], device: device)) }
        }
        self.holds = holds
        onEvent(.holding(holds))
    }
}
