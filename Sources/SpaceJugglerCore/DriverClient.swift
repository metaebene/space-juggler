import AppKit
import SpaceJugglerProtocol

/// Space Juggler as the one client of 3Dconnexion's driver while its helper holds the SpaceMice (ADR-0004): a *manual*
/// client (`'++++'`, takeover mode), because Space Juggler is never the frontmost app and a background `'****'` client
/// gets nothing (stagehand findings, "Routing"). Activated with `'3dac'` while one of Space Juggler's clients holds the
/// SpaceMouse, deactivated with `'3ddc'` otherwise, so the frontmost app's own driver client gets it back. While active
/// it starves every other client of the driver (measured in stagehand with Trainer).
///
/// The classic client API (`3DconnexionClient.framework`) is loaded at runtime, so Space Juggler runs without it; it is
/// signed by another team, hence the entitlement `disable-library-validation`. Registration waits a moment after the
/// helper is found: helper 1.4.2 crashed on a registration made while an app was launching (Space Shuttle ADR-0008).
@MainActor
final class DriverClient {
    nonisolated static let frameworkPath = "/Library/Frameworks/3DconnexionClient.framework/3DconnexionClient"
    nonisolated static let helperBundleID = "com.3dconnexion.driver.helper"
    nonisolated static let manualSignature: UInt32 = 0x2B2B_2B2B        // '++++' kConnexionClientManual
    nonisolated static let modeTakeOver: UInt16 = 1                      // kConnexionClientModeTakeOver
    nonisolated static let maskAll: UInt32 = 0x3FFF                      // kConnexionMaskAll
    nonisolated static let maskAllButtons: UInt32 = 0xFFFF_FFFF          // kConnexionMaskAllButtons
    nonisolated static let messageDeviceState: UInt32 = 0x3364_5352      // '3dSR'
    nonisolated static let controlActivate: UInt32 = 0x3364_6163         // '3dac'
    nonisolated static let controlDeactivate: UInt32 = 0x3364_6463       // '3ddc'
    nonisolated static let controlSetLED: UInt32 = 0x3364_736C           // '3dsl'
    nonisolated static let registrationDelay = 1.0

    /// The one instance the C callbacks talk to; the client API has no context pointer.
    fileprivate static var current: DriverClient?

    /// The cap and the buttons as the driver reports them (buttons as a bitmap in the device's numbering).
    var onAxes: (SpaceMouseAxes) -> Void = { _ in }
    var onButtons: (UInt32) -> Void = { _ in }
    var log: (String) -> Void = { _ in }

    private var api: ConnexionAPI?
    private var clientID: UInt16 = 0
    private var wanted = false
    private var active = false
    private var starting = false

    var isRegistered: Bool { clientID != 0 }

    /// Whether 3Dconnexion's helper runs, which then holds every SpaceMouse. From NSWorkspace's list, the one the
    /// broker observes: `NSRunningApplication.runningApplications(withBundleIdentifier:)` missed the helper for seconds
    /// after it had appeared in that list (measured 2026-10-15), and no later change of the list corrected it.
    @MainActor static var helperRuns: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == helperBundleID && !$0.isTerminated }
    }

    func start() {
        guard api == nil, !starting else { return }
        starting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.registrationDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.starting else { return }
                self.starting = false
                self.register()
            }
        }
    }

    private func register() {
        guard Self.current == nil else { return log("driver: another client in this process") }
        let api: ConnexionAPI
        do {
            api = try ConnexionAPI.load(path: Self.frameworkPath)
        } catch {
            return log("driver: \(error)")
        }
        self.api = api
        Self.current = self
        let handlers = api.setHandlers(messageHandler, addedHandler, removedHandler, false)
        guard handlers == 0 else {
            self.api = nil
            Self.current = nil
            // -36 seen when the helper was not running (Space Shuttle, release 0.1).
            return log("driver: SetConnexionHandlers returned \(handlers)")
        }
        // With a name: registered without one from an app bundle, helper 1.4.4 crashed at once (2026-10-14, the
        // `insertObject: nil` seen with 1.4.2 too); the command-line probe always passed one and never crashed it.
        let name = Array(SpaceJuggler.appName.utf8.prefix(255))
        let pascal = [UInt8(name.count)] + name
        clientID = pascal.withUnsafeBufferPointer { api.register(Self.manualSignature, $0.baseAddress, Self.modeTakeOver, Self.maskAll) }
        guard clientID != 0 else {
            api.cleanup()
            self.api = nil
            Self.current = nil
            return log("driver: RegisterConnexionClient returned no client ID")
        }
        api.setButtonMask(clientID, Self.maskAllButtons)
        log("driver: registered as manual client \(clientID)")
        updateActivation()
    }

    /// Takes the driver's data (true) or leaves it to the frontmost app's own client (false).
    func want(_ wanted: Bool) {
        self.wanted = wanted
        updateActivation()
    }

    private func updateActivation() {
        guard clientID != 0, wanted != active else { return }
        active = wanted
        control(active ? Self.controlActivate : Self.controlDeactivate)
        log("driver: \(active ? "activated" : "deactivated")")
    }

    /// `'3dsl'`; the SpaceMouse Compact ignores it (stagehand findings).
    func setLED(_ on: Bool) {
        guard let api, clientID != 0 else { return }
        var result: Int32 = 0
        _ = api.control(clientID, Self.controlSetLED, on ? 1 : 0, &result)
    }

    func stop() {
        starting = false
        guard let api else { return }
        if clientID != 0 {
            if active { control(Self.controlDeactivate) }
            active = false
            api.unregister(clientID)
            clientID = 0
        }
        api.cleanup()
        self.api = nil
        if Self.current === self { Self.current = nil }
        log("driver: unregistered")
    }

    private func control(_ message: UInt32) {
        guard let api else { return }
        var result: Int32 = 0
        let status = api.control(clientID, message, 0, &result)
        if status != 0 { log("driver: control \(String(format: "0x%08X", message)) returned \(status)") }
    }

    fileprivate func received(_ state: ConnexionDeviceState) {
        guard active, state.client == Int(clientID) || state.client == 0 else { return }
        switch state.command {
        case ConnexionDeviceState.handleAxis: onAxes(state.axes)
        case ConnexionDeviceState.handleButtons: onButtons(state.buttonBits)
        default: break
        }
    }

    fileprivate func device(_ productID: UInt32, added: Bool) {
        log(String(format: "driver: device 0x%04X %@", productID, added ? "added" : "removed"))
    }
}

// MARK: - C callbacks (no context pointer; SetConnexionHandlers(…, useSeparateThread: false), so on the main thread)

private let messageHandler: ConnexionAPI.MessageHandler = { _, type, argument in
    guard type == DriverClient.messageDeviceState, let argument,
          let state = ConnexionDeviceState(UnsafeRawBufferPointer(start: argument, count: ConnexionDeviceState.size))
    else { return }
    DispatchQueue.main.async { MainActor.assumeIsolated { DriverClient.current?.received(state) } }
}

private let addedHandler: ConnexionAPI.DeviceHandler = { productID in
    DispatchQueue.main.async { MainActor.assumeIsolated { DriverClient.current?.device(productID, added: true) } }
}

private let removedHandler: ConnexionAPI.DeviceHandler = { productID in
    DispatchQueue.main.async { MainActor.assumeIsolated { DriverClient.current?.device(productID, added: false) } }
}

/// The functions of the classic client API we use, resolved with `dlopen`/`dlsym` so Space Juggler runs without the
/// framework (from stagehand's `spacemouse-probe` via Space Shuttle and Space Glider).
struct ConnexionAPI {
    typealias MessageHandler = @convention(c) (UInt32, UInt32, UnsafeMutableRawPointer?) -> Void
    typealias DeviceHandler = @convention(c) (UInt32) -> Void

    let setHandlers: @convention(c) (MessageHandler?, DeviceHandler?, DeviceHandler?, Bool) -> Int16
    let register: @convention(c) (UInt32, UnsafePointer<UInt8>?, UInt16, UInt32) -> UInt16
    let unregister: @convention(c) (UInt16) -> Void
    let cleanup: @convention(c) () -> Void
    let setButtonMask: @convention(c) (UInt16, UInt32) -> Void
    let control: @convention(c) (UInt16, UInt32, Int32, UnsafeMutablePointer<Int32>?) -> Int16

    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    static func load(path: String) throws -> ConnexionAPI {
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw LoadError(description: "3Dconnexion framework not loadable: \(String(cString: dlerror()))")
        }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw LoadError(description: "missing symbol \(name)") }
            return unsafeBitCast(address, to: T.self)
        }
        return try ConnexionAPI(
            setHandlers: symbol("SetConnexionHandlers", as: (@convention(c) (MessageHandler?, DeviceHandler?, DeviceHandler?, Bool) -> Int16).self),
            register: symbol("RegisterConnexionClient", as: (@convention(c) (UInt32, UnsafePointer<UInt8>?, UInt16, UInt32) -> UInt16).self),
            unregister: symbol("UnregisterConnexionClient", as: (@convention(c) (UInt16) -> Void).self),
            cleanup: symbol("CleanupConnexionHandlers", as: (@convention(c) () -> Void).self),
            setButtonMask: symbol("SetConnexionClientButtonMask", as: (@convention(c) (UInt16, UInt32) -> Void).self),
            control: symbol("ConnexionClientControl", as: (@convention(c) (UInt16, UInt32, Int32, UnsafeMutablePointer<Int32>?) -> Int16).self)
        )
    }
}
