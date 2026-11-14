import Foundation
import SpaceMouseKit

/// When a SpaceMouse that Space Juggler opened without seizing may be seized (ADR-0017). Pure; `Reports` keeps one
/// while the device is open but not seized and asks it.
///
/// Without 3Dconnexion's driver, macOS itself turns an unclaimed SpaceMouse into a pointer: a deflected cap moves the
/// mouse pointer or scrolls, and macOS repeats the last deflection it saw until a report of all zeros comes. Once the
/// device is seized, macOS gets no report at all; seized while the cap is deflected, macOS never sees it return and the
/// pointer wanders until the device goes away. So the device is seized only once macOS has seen the cap at rest:
///
/// - **quiet**: the last axis picture since the open was all zeros, or none came at all (a cap in its middle reports
///   zeros once and then nothing), no button is held, and no axis or button report came for `quiet`;
/// - **rested**: a worn cap that never reports zeros (ADR-0010) has stayed where `CapRest` takes its rest – within
///   `CapRest.wobble` for `CapRest.settle`, within `CapRest.reach` – and no button is held.
///
/// A cap a hand holds is neither: it is not seized until the hand lets go.
struct SeizeGate: Sendable, Equatable {
    /// How long after the last axis or button report a cap at zero counts as quiet: about fifteen report intervals of
    /// a deflected cap (it reports about every 16 ms, even while the deflection stays the same), so that a late report
    /// over Bluetooth does not look like a rest, and long enough for macOS to have taken the zeros before it hears
    /// nothing more. A cap untouched when its app comes to the front is seized after this.
    static let quiet: TimeInterval = 0.25

    /// Why the device may be seized now.
    enum Reason: String, Sendable, Equatable {
        /// The cap reported zeros, or nothing since the open, and stayed quiet.
        case quiet
        /// The cap stayed off its centre where `CapRest` takes its rest (ADR-0010).
        case rested
    }

    /// The last complete axis picture since the open, raw; nil while none came.
    private(set) var axes: SpaceMouseAxes?
    private var held: SpaceMouseButtons = []
    /// When the device was opened or last reported axes or buttons.
    private(set) var lastInput: TimeInterval
    /// The same rule as the holder's `CapRest`, on the raw axes, for a cap that never reports zeros.
    private var rest = CapRest()
    private var rested = false

    init(openedAt time: TimeInterval) {
        lastInput = time
    }

    /// A complete axis picture as the device sent it (not the deflection from the rest).
    mutating func axes(_ axes: SpaceMouseAxes, at time: TimeInterval) {
        self.axes = axes
        lastInput = time
        // Raw and non-zero, the deflection from the rest is zero only around a rest taken off the centre.
        rested = rest.corrected(axes, at: time) == .zero && rest.rest != .zero
    }

    /// The buttons held, after any button report.
    mutating func buttons(_ held: SpaceMouseButtons, at time: TimeInterval) {
        self.held = held
        lastInput = time
    }

    /// Whether the device may be seized at `time`, and why; nil while macOS might still be told of a deflection or a
    /// held button.
    func ready(at time: TimeInterval) -> Reason? {
        guard held.isEmpty else { return nil }
        if axes?.isZero ?? true { return time - lastInput >= Self.quiet ? .quiet : nil }
        return rested ? .rested : nil
    }

    /// When to look again after `time` if no report comes: when a cap at zero becomes quiet; while a button is held or
    /// the cap is off zero (a release comes with a report), a `quiet` later.
    func nextCheck(after time: TimeInterval) -> TimeInterval {
        let quietAt = lastInput + Self.quiet
        return quietAt > time ? quietAt : time + Self.quiet
    }
}
