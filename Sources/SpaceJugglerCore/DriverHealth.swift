import Foundation
import SpaceJugglerProtocol

/// Whether 3Dconnexion's driver can pass the SpaceMouse on while its helper holds it, and if not, why (ADR-0013).
/// Pure; the broker asks it whenever the helper or the registration changes, and every `checkInterval` while the
/// helper runs.
enum DriverHealth {
    /// A helper that has not finished launching this long after its launch hangs. It finishes within a second or two
    /// (helper 1.4.4, every launch in the broker logs since 2026-10-14); on 2026-11-07 one hung for over an hour.
    static let launchGrace: TimeInterval = 30
    /// The first registration after a login often fails once and then goes through (ADR-0012): a problem only from
    /// the third failure in a row, about 7 s after the first.
    static let failuresBeforeProblem = 3
    static let checkInterval: TimeInterval = 5

    struct Helper: Equatable {
        /// When it launched (or, not known, when the broker first saw it).
        var since: Date
        var finishedLaunching: Bool
    }

    /// The problem, if any; its `detail` stays the same while the problem does, so that it is told once.
    static func problem(helper: Helper?, registered: Bool, failures: Int, lastFailure: String?, now: Date) -> DriverProblem? {
        guard let helper else { return nil }
        if !helper.finishedLaunching, now.timeIntervalSince(helper.since) >= launchGrace {
            return DriverProblem(code: DriverProblem.helperNotResponding,
                                 detail: "3Dconnexion's helper has not finished launching (launched \(stamp(helper.since)))")
        }
        if !registered, failures >= failuresBeforeProblem {
            return DriverProblem(code: DriverProblem.driverNotAnswering,
                                 detail: "the registration with 3Dconnexion's driver keeps failing: \(lastFailure ?? "unknown")")
        }
        return nil
    }

    /// Local time, as the broker's log writes it.
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
