import XCTest
@testable import Ate

@MainActor
final class AddGenerationDeadlineTests: XCTestCase {
    /// Intentionally does not honor Task cancellation. The actual attempt owner,
    /// not a cooperative fake transport or a structured task group, must release UI.
    private final class SuspendedWork {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func finish() { continuation?.resume(); continuation = nil }
    }

    func testDeadlineReleasesUncooperativeImportPreservesInputAndRefusesLateSave() async throws {
        let suite = "AddGenerationDeadlineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drafts = DraftStore(defaults: defaults, enabled: true)
        let input = "https://lancewood.co.za/recipes/nespresso-hazelnut-coffee-and-chocolate-trifle-recipe/"
        drafts.begin(mode: "Link", text: input, imageData: nil)
        let attempt = DraftGenerationAttempt(), work = SuspendedWork()
        let started = expectation(description: "actual owner suspended"), expired = expectation(description: "deadline released UI")
        let returned = expectation(description: "late callback returned")
        var loading = true, error: String?, writes = 0, expirations = 0
        attempt.start(timeoutNanoseconds: 20_000_000, timedOut: {
            XCTAssertFalse(attempt.isRunning, "Revoke before presenting timeout")
            loading = false; error = AddRecipeSheet.generationTimeoutMessage
            expirations += 1; expired.fulfill()
        }) { token in
            started.fulfill()
            await work.wait()
            attempt.publish(token) { drafts.saveDraft(RecipeCard(title: "Late card")); writes += 1 }
            attempt.publish(token) { loading = true; error = "stale error"; writes += 1 }
            returned.fulfill()
        }
        await fulfillment(of: [started, expired], timeout: 2)
        XCTAssertFalse(loading); XCTAssertFalse(attempt.isRunning)
        XCTAssertTrue(error?.contains("Try again") == true)
        XCTAssertEqual(drafts.pending?.text, input); XCTAssertNil(drafts.draft)
        work.finish()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(writes, 0); XCTAssertEqual(expirations, 1)
        XCTAssertEqual(error, AddRecipeSheet.generationTimeoutMessage)
        XCTAssertEqual(drafts.pending?.text, input); XCTAssertNil(drafts.draft)
    }

    func testOldCompletionCannotStopOrPublishIntoExplicitRetry() async {
        let attempt = DraftGenerationAttempt(), old = SuspendedWork(), fresh = SuspendedWork()
        let started = expectation(description: "old started"), expired = expectation(description: "old expired")
        let retryStarted = expectation(description: "explicit retry started"), oldReturned = expectation(description: "old returned")
        let freshReturned = expectation(description: "fresh returned")
        var effects = [String]()
        attempt.start(timeoutNanoseconds: 20_000_000, timedOut: { expired.fulfill() }) { token in
            started.fulfill(); await old.wait()
            attempt.publish(token) { effects.append("old save/preview/error/finish") }
            oldReturned.fulfill()
        }
        await fulfillment(of: [started, expired], timeout: 2)
        attempt.start { token in
            retryStarted.fulfill(); await fresh.wait()
            attempt.publish(token) { effects.append("new result") }
            freshReturned.fulfill()
        }
        await fulfillment(of: [retryStarted], timeout: 2)
        old.finish()
        await fulfillment(of: [oldReturned], timeout: 2)
        XCTAssertTrue(attempt.isRunning)
        XCTAssertTrue(effects.isEmpty)
        fresh.finish()
        await fulfillment(of: [freshReturned], timeout: 2)
        XCTAssertEqual(effects, ["new result"])
    }

    func testCompletedPrimaryCancelsDeadlineWithoutRevokingItsSpreadChild() async {
        let attempt = DraftGenerationAttempt(), child = SuspendedWork()
        let childStarted = expectation(description: "spread child started"), childReturned = expectation(description: "spread child returned")
        let expired = expectation(description: "completed request must not time out"); expired.isInverted = true
        var effects = 0
        attempt.start(timeoutNanoseconds: 20_000_000, timedOut: { expired.fulfill() }) { token in
            attempt.startChild(token) {
                childStarted.fulfill(); await child.wait()
                attempt.publish(token) { effects += 1 }; childReturned.fulfill()
            }
        }
        await fulfillment(of: [childStarted], timeout: 2)
        await fulfillment(of: [expired], timeout: 0.1)
        XCTAssertFalse(attempt.isRunning)
        child.finish()
        await fulfillment(of: [childReturned], timeout: 2)
        XCTAssertEqual(effects, 1)
        attempt.invalidate()
    }

    func testDiscardCancelsDeadlineAndKeepsDefaultSixtySecondProductBound() async {
        XCTAssertEqual(AddRecipeSheet.generationTimeoutNanoseconds, 60_000_000_000)
        XCTAssertTrue(AddRecipeSheet.generationTimeoutMessage.contains("Nothing was saved"))
        let attempt = DraftGenerationAttempt(), work = SuspendedWork()
        let started = expectation(description: "started"), returned = expectation(description: "cancelled work returned")
        let expired = expectation(description: "discard must not publish timeout"); expired.isInverted = true
        attempt.start(timeoutNanoseconds: 20_000_000, timedOut: { expired.fulfill() }) { token in
            started.fulfill(); await work.wait()
            XCTAssertFalse(attempt.publish(token) { XCTFail("Discarded result published") })
            returned.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        attempt.invalidate()
        await fulfillment(of: [expired], timeout: 0.1)
        work.finish()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertFalse(attempt.isRunning)
    }
}
