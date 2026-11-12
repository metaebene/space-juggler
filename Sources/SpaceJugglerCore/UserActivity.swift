import Foundation
import IOKit.pwr_mgt
import SpaceMouseKit

/// When the input of a SpaceMouse is to be told to macOS, and for how long the screen saver waits after it (ADR-0015,
/// ADR-0016). A seized device's input never reaches the system's idle timer, so a Mac steered only with a SpaceMouse
/// started its screen saver and turned its display off. Pure; `UserActivity` keeps one and asks it.
struct UserActivityPacing: Sendable, Equatable {
    /// At most one declaration in this time: the shortest idle time macOS offers is a minute.
    static let interval: TimeInterval = 10
    /// The shortest and longest time the screen saver is held off after the last input (ADR-0016).
    static let holds: ClosedRange<TimeInterval> = 60...600
    /// The screen saver's idle time when the user never set one.
    static let defaultScreenSaverIdle: TimeInterval = 1200

    private(set) var lastDeclared: Date?

    /// Axes count while the cap is off its rest (a zero deflection is the cap let go); buttons count on every change.
    mutating func axes(_ axes: SpaceMouseAxes, at now: Date) -> Bool {
        axes.isZero ? false : due(at: now)
    }

    mutating func buttons(at now: Date) -> Bool {
        due(at: now)
    }

    private mutating func due(at now: Date) -> Bool {
        if let lastDeclared, now.timeIntervalSince(lastDeclared) < Self.interval { return false }
        lastDeclared = now
        return true
    }

    /// How long after the last input the screen saver is held off: the user's own idle time, so that it starts no
    /// sooner than after a mouse; "never" (0) and anything shorter than a minute as a minute, and at most ten minutes,
    /// because the same hold keeps the display from sleeping.
    static func hold(screenSaverIdle: TimeInterval?) -> TimeInterval {
        let idle = screenSaverIdle ?? defaultScreenSaverIdle
        return min(max(idle, holds.lowerBound), holds.upperBound)
    }
}

/// Tells macOS that someone works at the Mac while a SpaceMouse moves (ADR-0015, ADR-0016): a declaration of the
/// user's activity, which wakes the display and resets the power manager's idle time, and a
/// `PreventUserIdleDisplaySleep` assertion held until `hold` after the last input. The screen saver measures idle
/// time from the HID system alone and starts unless such an assertion is held (loginwindow: "PMNoDisplaySleepEnabled
/// so do not launch screen saver"); a declaration alone did not keep it off (Tim, 2026-11-12). Never an event:
/// nothing reaches another app (ADR-0002).
@MainActor
final class UserActivity {
    /// What Space Juggler asks of the power manager; tests record instead.
    struct Power {
        var declare: (inout IOPMAssertionID) -> IOReturn
        var holdDisplay: (inout IOPMAssertionID) -> IOReturn
        var release: (IOPMAssertionID) -> Void
        var screenSaverIdle: () -> TimeInterval?
        var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static var system: Power { Power(
            declare: { IOPMAssertionDeclareUserActivity("SpaceMouse input" as CFString, kIOPMUserActiveLocal, &$0) },
            holdDisplay: {
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn), "SpaceMouse input" as CFString, &$0)
            },
            release: { _ = IOPMAssertionRelease($0) },
            screenSaverIdle: {
                // The idle time of System Settings → Lock Screen, per host; 0 is "never".
                let value = CFPreferencesCopyValue("idleTime" as CFString, "com.apple.screensaver" as CFString,
                                                   kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
                return (value as? NSNumber)?.doubleValue
            },
            after: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
            }) }
    }

    private var pacing = UserActivityPacing()
    private let power: Power
    private var activity = IOPMAssertionID(0)
    private var display: IOPMAssertionID?
    /// When the display assertion goes; pushed on by every declaration.
    private var releaseAt: Date?
    var log: (String) -> Void = { _ in }
    private var failed = false

    init(power: Power = .system) {
        self.power = power
    }

    var holdsDisplay: Bool { display != nil }

    func axes(_ axes: SpaceMouseAxes, now: Date = Date()) {
        if pacing.axes(axes, at: now) { declare(at: now) }
    }

    func buttons(now: Date = Date()) {
        if pacing.buttons(at: now) { declare(at: now) }
    }

    private func declare(at now: Date) {
        var result = power.declare(&activity)
        if display == nil {
            var id = IOPMAssertionID(0)
            let held = power.holdDisplay(&id)
            if held == kIOReturnSuccess { display = id } else { result = held }
        }
        // Logged once per run of failures, not six times a minute.
        if result != kIOReturnSuccess, !failed { log("telling macOS of SpaceMouse input failed: \(result)") }
        failed = result != kIOReturnSuccess
        guard display != nil else { return }
        let hold = UserActivityPacing.hold(screenSaverIdle: power.screenSaverIdle())
        let wasPending = releaseAt != nil
        releaseAt = now.addingTimeInterval(hold)
        if !wasPending { schedule(after: hold) }
    }

    /// One pending check at a time: it lets go once the last declaration is `hold` old, else waits for the rest.
    private func schedule(after delay: TimeInterval) {
        power.after(delay) { [weak self] in self?.check() }
    }

    func check(now: Date = Date()) {
        guard let releaseAt else { return }
        let left = releaseAt.timeIntervalSince(now)
        if left > 0 { return schedule(after: left) }
        self.releaseAt = nil
        if let display { power.release(display) }
        display = nil
    }
}
