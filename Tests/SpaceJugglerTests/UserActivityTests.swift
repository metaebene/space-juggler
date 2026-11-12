import Foundation
import IOKit.pwr_mgt
import SpaceMouseKit
import Testing
@testable import SpaceJugglerCore

/// Input from a seized SpaceMouse told to macOS as the user's activity, and the screen saver held off (ADR-0015,
/// ADR-0016).
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

    @Test func theHoldIsTheUsersIdleTimeBetweenOneAndTenMinutes() {
        let holds = [60, 300, 7200, 0, 30].map { UserActivityPacing.hold(screenSaverIdle: $0) }
        #expect(holds == [60, 300, 600, 60, 60])
        #expect(UserActivityPacing.hold(screenSaverIdle: nil) == 600)
    }

    /// Records what the power manager is asked; scheduled checks run only when a test calls `check`.
    @MainActor final class FakePower {
        var declared: [IOPMAssertionID] = []
        var held = 0
        var released: [IOPMAssertionID] = []
        var scheduled: [TimeInterval] = []
        var declareResult = kIOReturnSuccess
        var idle: TimeInterval? = 60

        var power: UserActivity.Power {
            UserActivity.Power(
                declare: { [unowned self] id in
                    MainActor.assumeIsolated {
                        declared.append(id)
                        id = 7
                        return declareResult
                    }
                },
                holdDisplay: { [unowned self] id in
                    MainActor.assumeIsolated {
                        held += 1
                        id = IOPMAssertionID(100 + held)
                        return kIOReturnSuccess
                    }
                },
                release: { [unowned self] id in MainActor.assumeIsolated { released.append(id) } },
                screenSaverIdle: { [unowned self] in MainActor.assumeIsolated { idle } },
                after: { [unowned self] delay, _ in MainActor.assumeIsolated { scheduled.append(delay) } })
        }
    }

    @MainActor @Test func theDisplayIsHeldUntilTheIdleTimeAfterTheLastInput() {
        let fake = FakePower()
        let activity = UserActivity(power: fake.power)
        // 50 s of steering, then nothing.
        for second in stride(from: 0.0, through: 50, by: 1) { activity.axes(moved, now: start + second) }
        #expect(fake.held == 1)
        #expect(fake.declared == [0, 7, 7, 7, 7, 7])
        // One check pending, 60 s after the first input; at 60 s the last declaration (50 s) is 50 s old: wait 50 more.
        #expect(fake.scheduled == [60])
        activity.check(now: start + 60)
        #expect(fake.scheduled == [60, 50])
        #expect(activity.holdsDisplay)
        activity.check(now: start + 110)
        #expect(fake.released == [101])
        #expect(!activity.holdsDisplay)
        // Moving again holds it anew.
        activity.buttons(now: start + 200)
        #expect(fake.held == 2)
        #expect(activity.holdsDisplay)
    }

    @MainActor @Test func aFailureIsLoggedOncePerRun() {
        let fake = FakePower()
        fake.declareResult = kIOReturnError
        let activity = UserActivity(power: fake.power)
        var logged: [String] = []
        activity.log = { logged.append($0) }
        activity.axes(moved, now: start)
        activity.axes(moved, now: start + 10)
        fake.declareResult = kIOReturnSuccess
        activity.axes(moved, now: start + 20)
        fake.declareResult = kIOReturnError
        activity.axes(moved, now: start + 30)
        #expect(logged.count == 2)
    }
}
