import XCTest
@testable import Ate

@MainActor
final class DraftRepairAttemptTests: XCTestCase {
    /// Deliberately ignores cancellation, like an uncooperative model callback.
    private final class DelayedBackend {
        var continuation: CheckedContinuation<RecipeCard, Never>?
        func parse() async -> RecipeCard {
            await withCheckedContinuation { continuation = $0 }
        }
        func complete(_ card: RecipeCard) {
            continuation?.resume(returning: card)
            continuation = nil
        }
    }

    func testDiscardThenLateBackendCannotResurrectPersistentDraft() async throws {
        let suite = "DraftRepairAttemptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drafts = DraftStore(defaults: defaults, enabled: true)
        let original = RecipeCard(title: "Retained salad", source: .appleIntelligence)
        drafts.saveDraft(original)
        let backend = DelayedBackend()
        let attempt = DraftRepairAttempt()
        var applied = false
        let started = expectation(description: "backend started")
        let returned = expectation(description: "cancel-ignoring backend returned")
        attempt.start(operation: {
            started.fulfill()
            let result = await backend.parse()
            returned.fulfill()
            return result
        }, apply: { card in
            applied = true
            drafts.saveDraft(card)
        }, failed: { _ in XCTFail("Invalidated result must not publish an error") },
           finished: { XCTFail("Invalidated result must not mutate dismissed UI") })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertNotNil(backend.continuation)
        attempt.invalidate() // Same ordering as Discard and onDisappear.
        drafts.clear()
        backend.complete(original)
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertFalse(applied)
        XCTAssertNil(drafts.draft)
        XCTAssertNil(drafts.pending)
        XCTAssertFalse(attempt.isRunning)
    }

    func testCurrentAttemptCanApplyAndFinish() async {
        let attempt = DraftRepairAttempt()
        let done = expectation(description: "current repair finished")
        var applied = false
        attempt.start(operation: { RecipeCard(title: "Salad", source: .appleIntelligence) },
            apply: { _ in applied = true }, failed: { _ in XCTFail("Unexpected error") },
            finished: { done.fulfill() })
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(applied)
        XCTAssertFalse(attempt.isRunning)
    }
}
