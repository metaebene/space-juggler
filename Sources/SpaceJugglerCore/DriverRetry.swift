import Foundation

/// When to try registering with 3Dconnexion's driver again after it failed, and which failures to log (ADR-0012).
/// A failed registration leaves Space Juggler in driver mode without a client of the driver: nothing reaches anyone
/// until it succeeds. Pure; `DriverClient` keeps one and asks it.
struct DriverRetry: Sendable, Equatable {
    /// The waits after the first, second … failure; the last one repeats.
    static let delays: [TimeInterval] = [2, 5, 10, 30, 60, 120, 300, 600, 1800]
    /// An app that wants the SpaceMouse (a holder appears) brings the next attempt forward, but no sooner than this
    /// after the last one.
    static let soonest: TimeInterval = 10

    /// Failures since the last success or since the helper came.
    private(set) var failures = 0
    private(set) var lastAttempt: Date?
    /// Why the last attempt failed; nil after a success.
    private(set) var lastReason: String?
    private var lastLogged: String?

    /// What follows a failure: how long to wait, and the line for the log, if this one is to be logged – the first,
    /// any with another reason than the last one logged, then only the 2nd, 4th, 8th … so that a driver failing for
    /// days writes a few lines, not thousands.
    struct Next: Equatable {
        var delay: TimeInterval
        var log: String?
    }

    mutating func failed(_ reason: String, at now: Date) -> Next {
        failures += 1
        lastAttempt = now
        lastReason = reason
        let delay = Self.delays[min(failures, Self.delays.count) - 1]
        let changed = reason != lastLogged
        guard changed || failures & (failures - 1) == 0 else { return Next(delay: delay, log: nil) }
        lastLogged = reason
        let count = failures == 1 ? "" : ", failed \(failures) times"
        return Next(delay: delay, log: "driver: \(reason)\(count); trying again in \(Self.spoken(delay))")
    }

    /// Whether an attempt may come before its time: only after a failure and not within `soonest` of the last one.
    func mayTryEarly(at now: Date) -> Bool {
        guard failures > 0, let lastAttempt else { return false }
        return now.timeIntervalSince(lastAttempt) >= Self.soonest
    }

    /// A registration went through: the failures before it, and a fresh start.
    mutating func succeeded() -> Int {
        defer { self = DriverRetry() }
        return failures
    }

    static func spoken(_ delay: TimeInterval) -> String {
        delay < 60 ? "\(Int(delay)) s" : "\(Int(delay / 60)) min"
    }
}
