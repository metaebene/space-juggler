import Foundation
import Testing
@testable import SpaceJugglerCore

/// The registration with 3Dconnexion's driver tried again after it failed (ADR-0012).
struct DriverRetryTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func theWaitsGrowAndThenStay() {
        var retry = DriverRetry()
        let delays = (0..<12).map { retry.failed("SetConnexionHandlers returned -36", at: start + Double($0)).delay }
        #expect(delays == [2, 5, 10, 30, 60, 120, 300, 600, 1800, 1800, 1800, 1800])
    }

    @Test func aFailureThatGoesOnIsLoggedEverLessOften() {
        var retry = DriverRetry()
        let logged = (1...1000).compactMap { n in
            retry.failed("SetConnexionHandlers returned -36", at: start + Double(n)).log.map { _ in n }
        }
        #expect(logged == [1, 2, 4, 8, 16, 32, 64, 128, 256, 512])
        var first = DriverRetry()
        #expect(first.failed("SetConnexionHandlers returned -36", at: start).log
                == "driver: SetConnexionHandlers returned -36; trying again in 2 s")
    }

    @Test func aNewReasonIsLoggedAtOnce() {
        var retry = DriverRetry()
        _ = retry.failed("SetConnexionHandlers returned -36", at: start)
        _ = retry.failed("SetConnexionHandlers returned -36", at: start + 2)
        #expect(retry.failed("SetConnexionHandlers returned -36", at: start + 7).log == nil)
        #expect(retry.failed("RegisterConnexionClient returned no client ID", at: start + 17).log
                == "driver: RegisterConnexionClient returned no client ID, failed 4 times; trying again in 30 s")
    }

    @Test func anAppThatWantsTheSpaceMouseBringsTheAttemptForwardButNotTooOften() {
        var retry = DriverRetry()
        #expect(!retry.mayTryEarly(at: start))
        for n in 0..<5 { _ = retry.failed("SetConnexionHandlers returned -36", at: start + Double(n)) }
        #expect(!retry.mayTryEarly(at: start + 4 + DriverRetry.soonest - 1))
        #expect(retry.mayTryEarly(at: start + 4 + DriverRetry.soonest))
    }

    @Test func successStartsAfresh() {
        var retry = DriverRetry()
        for n in 0..<3 { _ = retry.failed("SetConnexionHandlers returned -36", at: start + Double(n)) }
        #expect(retry.succeeded() == 3)
        #expect(retry == DriverRetry())
        #expect(retry.failed("SetConnexionHandlers returned -36", at: start + 10).delay == 2)
        #expect(DriverRetry.spoken(1800) == "30 min")
    }
}
