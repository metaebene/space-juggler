import Foundation
import IOKit.pwr_mgt
import SpaceMouseKit

/// When the input of a SpaceMouse is to be told to macOS as the user's activity (ADR-0015). A seized device's input
/// never reaches the system's idle timer, so a Mac steered only with a SpaceMouse started its screen saver and turned
/// its display off (Kugelblitz report f25fb962, 2026-11-12). Pure; `UserActivity` keeps one and asks it.
struct UserActivityPacing: Sendable, Equatable {
    /// At most one declaration in this time: the shortest idle time macOS offers is a minute.
    static let interval: TimeInterval = 10

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
}

/// Tells macOS that someone works at the Mac while a SpaceMouse moves, as a moved mouse does: the screen saver stays
/// off, the display stays on or wakes up (ADR-0015). Only a declaration of activity, never an event: nothing reaches
/// another app (ADR-0002).
@MainActor
final class UserActivity {
    private var pacing = UserActivityPacing()
    private var assertion = IOPMAssertionID(0)
    /// What declares; tests count instead.
    private let declare: (inout IOPMAssertionID) -> IOReturn
    var log: (String) -> Void = { _ in }
    private var failed = false

    init(declare: @escaping (inout IOPMAssertionID) -> IOReturn = UserActivity.declareToSystem) {
        self.declare = declare
    }

    func axes(_ axes: SpaceMouseAxes, now: Date = Date()) {
        if pacing.axes(axes, at: now) { declareNow() }
    }

    func buttons(now: Date = Date()) {
        if pacing.buttons(at: now) { declareNow() }
    }

    private func declareNow() {
        let result = declare(&assertion)
        // Logged once per run of failures, not ten times a minute.
        if result != kIOReturnSuccess, !failed { log("declaring user activity failed: \(result)") }
        failed = result != kIOReturnSuccess
    }

    /// The same assertion again and again: the system lets it go by itself once no more activity comes.
    nonisolated static func declareToSystem(_ assertion: inout IOPMAssertionID) -> IOReturn {
        IOPMAssertionDeclareUserActivity("SpaceMouse input" as CFString, kIOPMUserActiveLocal, &assertion)
    }
}
