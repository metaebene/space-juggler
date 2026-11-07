import Foundation
import SpaceJugglerProtocol
import Testing
@testable import SpaceJugglerCore

/// Why 3Dconnexion's driver passes nothing on (ADR-0013).
struct DriverHealthTests {
    let launch = Date(timeIntervalSinceReferenceDate: 0)

    private func problem(finished: Bool = true, after seconds: TimeInterval, registered: Bool = false, failures: Int = 0,
                         helper: Bool = true) -> DriverProblem? {
        DriverHealth.problem(helper: helper ? .init(since: launch, finishedLaunching: finished) : nil, registered: registered,
                             failures: failures, lastFailure: "SetConnexionHandlers returned -36", now: launch + seconds)
    }

    @Test func withoutTheHelperThereIsNone() {
        #expect(problem(finished: false, after: 3600, failures: 40, helper: false) == nil)
    }

    @Test func aHelperStillLaunchingHangsOnlyAfterTheGrace() {
        #expect(problem(finished: false, after: DriverHealth.launchGrace - 1) == nil)
        #expect(problem(finished: false, after: DriverHealth.launchGrace)?.code == DriverProblem.helperNotResponding)
        #expect(problem(finished: true, after: 3600) == nil)
    }

    @Test func aHangingHelperComesBeforeTheFailures() {
        #expect(problem(finished: false, after: 60, failures: 10)?.code == DriverProblem.helperNotResponding)
    }

    @Test func failuresAreAProblemFromTheThird() {
        #expect(problem(after: 60, failures: DriverHealth.failuresBeforeProblem - 1) == nil)
        let third = problem(after: 60, failures: DriverHealth.failuresBeforeProblem)
        #expect(third?.code == DriverProblem.driverNotAnswering)
        #expect(third?.detail.hasSuffix("SetConnexionHandlers returned -36") == true)
        #expect(problem(after: 60, registered: true, failures: 5) == nil)
    }

    /// Told once: the same problem later is the same value.
    @Test func theDetailStaysWhileTheProblemDoes() {
        #expect(problem(finished: false, after: 31) == problem(finished: false, after: 4000))
        #expect(problem(after: 60, failures: 3) == problem(after: 600, failures: 30))
    }

    /// An older client ignores the field, a client reading an older broker gets nil, an unknown code still decodes.
    @Test func theFieldIsOptionalOnTheWire() throws {
        let device = SpaceMouseDevice(id: "port:256f:c635@1", vendorID: 0x256F, productID: 0xC635, name: "SpaceMouse Compact",
                                      transport: "USB", state: "driver",
                                      driverProblem: DriverProblem(code: "somethingNew", detail: "later"))
        let decoded = try JSONDecoder().decode(SpaceMouseDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded.driverProblem?.code == "somethingNew")
        var old = device
        old.driverProblem = nil
        let json = try JSONEncoder().encode(old)
        #expect(!String(decoding: json, as: UTF8.self).contains("driverProblem"))
        #expect(try JSONDecoder().decode(SpaceMouseDevice.self, from: json).driverProblem == nil)
    }
}
