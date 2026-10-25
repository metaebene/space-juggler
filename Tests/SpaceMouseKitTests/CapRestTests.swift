import Testing
@testable import SpaceMouseKit

/// Where the cap rests (ADR-0010).
struct CapRestTests {
    /// Reports every 16 ms from `start` for `seconds`, each the cap at `axes`; the last one passed on.
    private func hold(_ rest: inout CapRest, _ axes: SpaceMouseAxes, from start: Double, for seconds: Double) -> SpaceMouseAxes {
        var passed = SpaceMouseAxes.zero
        var t = start
        while t <= start + seconds {
            passed = rest.corrected(axes, at: t)
            t += 0.016
        }
        return passed
    }

    @Test func aCapStayingOffItsCentreBecomesItsRest() {
        // A report of Kugelblitz (2026-10-25): an old SpaceNavigator untouched a little beyond the client's dead zone.
        var rest = CapRest()
        let off = SpaceMouseAxes(y: 32, rz: -30)
        #expect(hold(&rest, off, from: 0, for: 1) == off, "not yet: a hand may hold it")
        #expect(hold(&rest, off, from: 1, for: 1) == .zero)
        #expect(rest.rest == off)
        #expect(rest.corrected(SpaceMouseAxes(y: 35, rz: -28), at: 2.1) == .zero, "its wobble is rest too")
        // A hand from there: the deflection from the rest.
        #expect(rest.corrected(SpaceMouseAxes(x: 200, y: 32, rz: -30), at: 2.2) == SpaceMouseAxes(x: 200))
        // The device in its middle takes the rest back.
        #expect(rest.corrected(.zero, at: 2.3) == .zero)
        #expect(rest.rest == .zero)
        #expect(rest.corrected(off, at: 2.4) == off)
    }

    @Test func aMovingCapIsNoRest() {
        var rest = CapRest()
        var t = 0.0
        for i in 0..<300 {
            _ = rest.corrected(SpaceMouseAxes(x: 20 + (i % 20)), at: t)   // a slow push, back and forth
            t += 0.016
        }
        #expect(rest.rest == .zero)
    }

    @Test func aCapHeldFarOutIsNoRest() {
        var rest = CapRest()
        let pushed = SpaceMouseAxes(z: 300)
        #expect(hold(&rest, pushed, from: 0, for: 5) == pushed)
        #expect(rest.rest == .zero)
    }
}
