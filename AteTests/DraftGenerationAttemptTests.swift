import XCTest
@testable import Ate

@MainActor
final class DraftGenerationAttemptTests: XCTestCase {
    @MainActor
    private final class DelayedBackend {
        var continuation: CheckedContinuation<RecipeCard, Never>?
        func parse(ready: () -> Void) async -> RecipeCard {
            await withCheckedContinuation {
                continuation = $0
                // Readiness means complete() can resume this exact suspended call.
                ready()
            }
        }
        func complete() {
            XCTAssertNotNil(continuation, "Complete only after the delayed call installs its continuation")
            continuation?.resume(returning: RecipeCard(title: "Late recipe", source: .appleIntelligence))
            continuation = nil
        }
    }

    func testDiscardSuppressesLateDraftPreviewErrorAndFinishEvenWhenBackendIgnoresCancellation() async throws {
        let suite = "DraftGenerationAttemptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drafts = DraftStore(defaults: defaults, enabled: true)
        drafts.begin(mode: "Prompt", text: "Test dish", imageData: nil)
        let attempt = DraftGenerationAttempt(), backend = DelayedBackend()
        let started = expectation(description: "started"), done = expectation(description: "late callback settled")
        var effects = 0
        attempt.start { token in
            let card = await backend.parse(ready: { started.fulfill() })
            // Same admission boundary used by UI callbacks and terminal cleanup.
            attempt.publish(token) { drafts.saveDraft(card); effects += 1 }
            attempt.publish(token) { effects += 1 } // preview/error/finish must also refuse
            done.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        attempt.invalidate()
        drafts.clear()
        backend.complete()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertNil(drafts.pending); XCTAssertNil(drafts.draft)
        XCTAssertEqual(effects, 0)
        XCTAssertFalse(attempt.isRunning)
    }

    func testDisappearKeepsRetryInputButLateResultCannotReplaceIt() async throws {
        let suite = "DraftGenerationAttemptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drafts = DraftStore(defaults: defaults, enabled: true)
        drafts.begin(mode: "Prompt", text: "Retained request", imageData: nil)
        let attempt = DraftGenerationAttempt(), backend = DelayedBackend()
        let started = expectation(description: "started"), done = expectation(description: "returned")
        attempt.start { token in
            let card = await backend.parse(ready: { started.fulfill() })
            attempt.publish(token) { drafts.saveDraft(card) }
            done.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        attempt.invalidate() // onDisappear does not clear persisted recovery input.
        backend.complete()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertNil(drafts.draft)
        XCTAssertEqual(drafts.pending?.text, "Retained request")
    }

    func testDuplicateStartRefusesAndOldCompletionCannotAdmitEffectsDuringNewAttempt() async {
        let attempt = DraftGenerationAttempt(), old = DelayedBackend(), fresh = DelayedBackend()
        let firstStarted = expectation(description: "old started"), newStarted = expectation(description: "new started")
        let oldDone = expectation(description: "old returned"), newDone = expectation(description: "new returned")
        var starts = 0, effects = 0
        attempt.start { token in
            starts += 1
            _ = await old.parse(ready: { firstStarted.fulfill() })
            attempt.publish(token) { effects += 100 }
            oldDone.fulfill()
        }
        attempt.start { _ in XCTFail("Duplicate concurrent start must be ignored") }
        await fulfillment(of: [firstStarted], timeout: 2)
        attempt.invalidate()
        attempt.start { token in
            starts += 1
            _ = await fresh.parse(ready: { newStarted.fulfill() })
            attempt.publish(token) { effects += 1 }
            newDone.fulfill()
        }
        await fulfillment(of: [newStarted], timeout: 2)
        old.complete()
        await fulfillment(of: [oldDone], timeout: 2)
        XCTAssertTrue(attempt.isRunning, "Old cleanup must not release the new task")
        fresh.complete()
        await fulfillment(of: [newDone], timeout: 2)
        XCTAssertEqual(starts, 2); XCTAssertEqual(effects, 1)
    }

    func testSpreadChildCannotWriteLibraryAfterInvalidation() async {
        let attempt = DraftGenerationAttempt(), child = DelayedBackend()
        let started = expectation(description: "child started"), done = expectation(description: "child returned")
        var cards: [RecipeCard] = []
        attempt.start { token in
            attempt.startChild(token) {
                let card = await child.parse(ready: { started.fulfill() })
                attempt.publish(token) { cards.append(card) }
                done.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 2)
        attempt.invalidate()
        child.complete()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(cards.isEmpty)
    }
}
