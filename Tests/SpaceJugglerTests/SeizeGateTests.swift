import Foundation
import Testing
@testable import SpaceJugglerCore
import SpaceMouseKit

/// When a SpaceMouse opened without seizing may be seized: only once macOS has seen the cap at rest (ADR-0017).
struct SeizeGateTests {
    /// The first report after seizing in a user's report (SpaceNavigator 046D:C626): a hand on the cap.
    let tilted = SpaceMouseAxes(y: -60, rx: -60)

    /// Reports every 16 ms from `start` for `seconds`, each the cap at `axes`; whether the gate opened at any of them
    /// or in the 16 ms between.
    private func report(_ gate: inout SeizeGate, _ axes: (Int) -> SpaceMouseAxes, from start: Double,
                        for seconds: Double) -> SeizeGate.Reason? {
        var t = start
        var i = 0
        while t <= start + seconds {
            gate.axes(axes(i), at: t)
            if let reason = gate.ready(at: t) ?? gate.ready(at: t + 0.015) { return reason }
            t += 0.016
            i += 1
        }
        return nil
    }

    @Test func aCapUntouchedIsSeizedOnceQuiet() {
        // A cap in its middle reported its zeros before the open and says nothing more.
        let gate = SeizeGate(openedAt: 10)
        #expect(gate.ready(at: 10) == nil)
        #expect(gate.ready(at: 10 + SeizeGate.quiet - 0.01) == nil, "macOS may still be taking the zeros")
        #expect(gate.ready(at: 10 + SeizeGate.quiet) == .quiet)
        #expect(gate.nextCheck(after: 10) == 10 + SeizeGate.quiet)
    }

    @Test func aCapHeldTiltedIsSeizedOnlyOnceItIsBackAtZero() {
        // Reproduced on 2026-11-14: the cap held tilted while an app takes the SpaceMouse. Seized at once, macOS kept
        // moving the pointer after the cap was let go; now the device waits until macOS has seen the zeros.
        var gate = SeizeGate(openedAt: 0)
        #expect(report(&gate, { _ in tilted }, from: 0, for: 5) == nil, "far out: a hand, never a rest")
        // A hand holds still near the centre but wobbles more than a resting cap.
        #expect(report(&gate, { SpaceMouseAxes(y: -20 - $0 % 10) }, from: 5, for: 5) == nil)
        #expect(gate.nextCheck(after: 11) == 11 + SeizeGate.quiet, "off zero: looked at again a quiet later")
        gate.axes(.zero, at: 10)
        #expect(gate.ready(at: 10) == nil)
        #expect(gate.ready(at: 10.1) == nil)
        #expect(gate.nextCheck(after: 10.1) == 10 + SeizeGate.quiet)
        #expect(gate.ready(at: 10 + SeizeGate.quiet) == .quiet)
    }

    @Test func aCapPassingThroughZeroIsNoRest() {
        var gate = SeizeGate(openedAt: 0)
        gate.axes(SpaceMouseAxes(ry: -40), at: 0.5)
        gate.axes(.zero, at: 0.516)
        gate.axes(SpaceMouseAxes(ry: 40), at: 0.532)
        #expect(gate.ready(at: 2) == nil, "its last picture is off zero")
    }

    @Test func aWornCapIsSeizedOnceItRestsOffItsCentre() {
        // ADR-0010: an old SpaceNavigator untouched a little off its centre never reports zeros.
        var gate = SeizeGate(openedAt: 0)
        let off = SpaceMouseAxes(y: 32, rz: -30)
        #expect(report(&gate, { _ in off }, from: 0, for: CapRest.settle - 0.05) == nil)
        #expect(report(&gate, { _ in off }, from: CapRest.settle - 0.034, for: 0.1) == .rested)
    }

    @Test func aHeldButtonWaitsForItsRelease() {
        // macOS might take a button for a click: seized while held, it would never see the release.
        var gate = SeizeGate(openedAt: 0)
        gate.buttons([.left], at: 0.1)
        #expect(gate.ready(at: 5) == nil)
        #expect(gate.nextCheck(after: 5) == 5 + SeizeGate.quiet)
        gate.buttons([], at: 5)
        #expect(gate.ready(at: 5.1) == nil)
        #expect(gate.ready(at: 5 + SeizeGate.quiet) == .quiet)

        var worn = SeizeGate(openedAt: 0)
        worn.buttons([.right], at: 0)
        #expect(report(&worn, { _ in SpaceMouseAxes(y: 32, rz: -30) }, from: 0, for: 3) == nil)
    }
}
