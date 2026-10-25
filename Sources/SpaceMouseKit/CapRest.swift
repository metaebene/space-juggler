import Foundation

/// Where the cap rests (ADR-0010). Read raw, an older cap whose rest has wandered off its centre keeps reporting a
/// small deflection while nobody touches it – 3Dconnexion's driver zeroes that, a raw reader does not, and a client
/// sees a hand that never lets go. A deflection that stays within `wobble` for `settle` seconds, no farther than
/// `reach` from the centre, becomes the cap's rest: what is passed on is the deflection from it. A report of all
/// zeros is the device saying it is in the middle and takes the rest back to zero.
public struct CapRest: Sendable, Equatable {
    /// The deflection taken as the cap's middle; zero until the cap has stayed somewhere else.
    public private(set) var rest = SpaceMouseAxes.zero
    private var still = SpaceMouseAxes.zero
    private var stillSince: TimeInterval?

    /// How far a resting cap's reports wander, per axis, in device units.
    public static let wobble = 4
    /// The farthest from the centre a rest is taken: a sixth of the full scale; beyond it a hand holds the cap.
    public static let reach = SpaceMouseAxes.deviceFullScale / 6
    /// How long the cap must stay before it counts as resting: longer than a hand holds it that still.
    public static let settle: TimeInterval = 1.5

    public init() {}

    /// The deflection from the rest for a report of `axes` at `time` (seconds of a monotonic clock).
    public mutating func corrected(_ axes: SpaceMouseAxes, at time: TimeInterval) -> SpaceMouseAxes {
        if axes.isZero {
            rest = .zero
            stillSince = nil
            return .zero
        }
        if let since = stillSince, zip(axes.all, still.all).allSatisfy({ abs($0 - $1) <= Self.wobble }) {
            if time - since >= Self.settle, axes.all.allSatisfy({ abs($0) <= Self.reach }) { rest = still }
        } else {
            still = axes
            stillSince = time
        }
        // Around the rest, its wobble is rest too.
        let off = zip(axes.all, rest.all).map { value, middle in
            middle != 0 && abs(value - middle) <= Self.wobble ? 0 : value - middle
        }
        return SpaceMouseAxes(x: off[0], y: off[1], z: off[2], rx: off[3], ry: off[4], rz: off[5])
    }
}
