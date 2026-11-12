import Foundation
import IOKit.pwr_mgt
import SpaceMouseKit
import Testing
@testable import SpaceJugglerCore

/// Input from a seized SpaceMouse told to macOS as the user's activity (ADR-0015).
struct UserActivityTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let moved = SpaceMouseAxes(x: 0, y: 120, z: 0, rx: 0, ry: 0, rz: 0)

    @Test func aMovingCapIsDeclaredAtMostEveryTenSeconds() {
        var pacing = UserActivityPacing()
        // Reports every 1/64 s (about the 16 ms of a SpaceNavigator, exact in binary) for 30 s.
        let times = (0...1920).map { start + Double($0) / 64 }
        let declared = times.filter { pacing.axes(moved, at: $0) }.map { $0.timeIntervalSince(start) }
        #expect(declared == [0, 10, 20, 30])
    }

    @Test func aCapLetGoIsNoActivity() {
        var pacing = UserActivityPacing()
        let answers = [pacing.axes(.zero, at: start), pacing.axes(.zero, at: start + 60), pacing.axes(moved, at: start + 61)]
        #expect(answers == [false, false, true])
    }

    @Test func buttonsCountAndShareTheInterval() {
        var pacing = UserActivityPacing()
        let answers = [pacing.buttons(at: start), pacing.axes(moved, at: start + 5), pacing.buttons(at: start + 9),
                       pacing.axes(moved, at: start + 10)]
        #expect(answers == [true, false, false, true])
    }

    @MainActor @Test func theSameAssertionIsDeclaredAgainAndAFailureLoggedOnce() {
        var assertions: [IOPMAssertionID] = []
        var result = kIOReturnError
        var logged: [String] = []
        let activity = UserActivity { assertion in
            assertions.append(assertion)
            assertion = 7
            return result
        }
        activity.log = { logged.append($0) }
        activity.axes(moved, now: start)
        activity.buttons(now: start + 10)
        result = kIOReturnSuccess
        activity.axes(moved, now: start + 20)
        result = kIOReturnError
        activity.axes(moved, now: start + 30)
        #expect(assertions == [0, 7, 7, 7])
        #expect(logged.count == 2)
    }
}
