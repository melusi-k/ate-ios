import XCTest
@testable import Ate

@MainActor
final class ResetAwareStartupTests: XCTestCase {
    private enum Fault: Error { case noAdmission }
    func testPendingUnknownResetNeverConstructsOrdinaryGraph() async {
        var events: [String] = []
        let startup = ResetAwareStartup<Int>(resume: { events.append("resume"); return .serverOutcomeUnverified },
            captureAdmission: { events.append("admit"); return UUID() }, validateAdmission: { _ in },
            buildGraph: { _ in events.append("build"); return 1 })
        await startup.start()
        XCTAssertEqual(events, ["resume"])
        guard case .blocked(.serverOutcomeUnverified) = startup.state else { return XCTFail("must block") }
    }
    func testCompletedResetAdmitsBeforeConstructorsAndPublishesReadyAfterValidation() async {
        var events: [String] = []
        let startup = ResetAwareStartup<Int>(resume: { events.append("resume"); return .completed },
            captureAdmission: { events.append("admit"); return UUID() },
            validateAdmission: { _ in events.append("validate") },
            buildGraph: { _ in events.append("build"); return 7 })
        await startup.start()
        XCTAssertEqual(events, ["resume", "admit", "validate", "build", "validate"])
        guard case .ready(7) = startup.state else { return XCTFail("wrong graph") }
    }
    func testControlAppearingBetweenResumeAndAdmissionRefusesBuild() async {
        var built = false
        let startup = ResetAwareStartup<Int>(resume: { nil },
            captureAdmission: { throw Fault.noAdmission }, validateAdmission: { _ in },
            buildGraph: { _ in built = true; return 1 })
        await startup.start()
        XCTAssertFalse(built)
        guard case .failed = startup.state else { return XCTFail("must fail closed") }
    }
    func testRepeatedStartCannotBuildOrResumeTwice() async {
        var builds = 0
        let startup = ResetAwareStartup<Int>(resume: { nil }, captureAdmission: { UUID() },
            validateAdmission: { _ in }, buildGraph: { _ in builds += 1; return builds })
        await startup.start()
        await startup.start()
        XCTAssertEqual(builds, 1)
    }
    func testPostFactoryLeaseFailureNeverPublishesReadyAndDoesNotClaimRollback() async {
        var validations = 0
        var built = false
        let startup = ResetAwareStartup<Int>(resume: { nil }, captureAdmission: { UUID() },
            validateAdmission: { _ in validations += 1; if validations == 2 { throw Fault.noAdmission } },
            buildGraph: { _ in built = true; return 1 })
        await startup.start()
        XCTAssertTrue(built, "post-check cannot undo earlier construction")
        guard case .failed(let message) = startup.state else { return XCTFail("must not publish ready") }
        XCTAssertFalse(message.contains("not been loaded"))
    }

}
