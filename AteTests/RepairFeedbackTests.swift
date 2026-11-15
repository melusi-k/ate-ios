import XCTest
@testable import Ate

@MainActor
final class RepairFeedbackTests: XCTestCase {
    private final class SuspendedBackend {
        var continuation: CheckedContinuation<RecipeCard, Never>?
        func parse() async -> RecipeCard { await withCheckedContinuation { continuation = $0 } }
        func complete() { continuation?.resume(returning: RecipeCard(title: "Late result")); continuation = nil }
    }

    func testAcceptedFeedbackNamesFixedAndRemainingGapsAndDoesNotRaiseConfidence() throws {
        var original = RecipeCard(title: "Tomato bread salad", servings: 2,
            ingredients: [.init(name: "tomato", quantity: 2, unit: "pcs"),
                          .init(name: "onion", quantity: 1, unit: "pcs"),
                          .init(name: "oil", quantity: 1, unit: "tbsp")],
            steps: [.init(order: 1, instruction: "Toss tomato and onion with bread and oil.", timeSeconds: nil)],
            source: .appleIntelligence)
        original.aiConfidence = 0.7
        var candidate = original
        candidate.ingredients.append(.init(name: "bread", quantity: 2, unit: "slice"))
        candidate.aiConfidence = 0.99
        let repaired = try RecipeDraftRepair.accept(candidate, replacing: original)
        let feedback = RepairFeedback.accepted(original: original, repaired: repaired)
        XCTAssertTrue(feedback.contains("Fixed 1 gap:"))
        XCTAssertTrue(feedback.contains("bread"))
        XCTAssertTrue(feedback.contains("Confirm this is the right dish"))
        XCTAssertFalse(feedback.contains("You can save"))
        XCTAssertEqual(repaired.aiConfidence, 0.7)
        XCTAssertTrue(RepairFeedback.confidenceExplanation.contains("Repairing doesn't change it"))
        original.aiConfidence = 0.95
        candidate.aiConfidence = 0.99
        let confident = try RecipeDraftRepair.accept(candidate, replacing: original)
        XCTAssertTrue(RepairFeedback.accepted(original: original, repaired: confident).contains("You can save"))
    }

    func testRepairDeadlineEndsSpinnerReportsAndSuppressesLateBackend() async {
        let attempt = DraftRepairAttempt(), backend = SuspendedBackend()
        let started = expectation(description: "backend started")
        let finished = expectation(description: "deadline ends spinner")
        let returned = expectation(description: "late backend returned")
        var message: String?, effects = 0, finishes = 0
        attempt.start(timeoutNanoseconds: 50_000_000, operation: {
            started.fulfill()
            let card = await backend.parse(); returned.fulfill(); return card
        }, apply: { _ in effects += 1 }, failed: { message = $0.localizedDescription }, finished: {
            finishes += 1; finished.fulfill()
        })
        await fulfillment(of: [started, finished], timeout: 2)
        XCTAssertEqual(message, RepairFeedback.timedOut)
        XCTAssertFalse(attempt.isRunning)
        backend.complete()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(finishes, 1)
    }

    func testRepairErrorFinishesOnceAndNoTimeoutMessageReplacesIt() async {
        let attempt = DraftRepairAttempt()
        let done = expectation(description: "model error finished")
        var message: String?, finishes = 0
        attempt.start(operation: { throw BackendError(message: "Apple Intelligence is busy. Wait a moment and try again.") },
                      apply: { _ in XCTFail("Error cannot publish a draft") },
                      failed: { message = $0.localizedDescription }, finished: { finishes += 1; done.fulfill() })
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(message?.contains("busy") == true)
        XCTAssertEqual(finishes, 1)
        XCTAssertFalse(attempt.isRunning)
    }

    func testGenerationDeadlineClosesPrimaryAndLatePublishWithoutDeletingInput() async {
        let attempt = DraftGenerationAttempt(), backend = SuspendedBackend()
        let started = expectation(description: "started"), expired = expectation(description: "timed out")
        let returned = expectation(description: "late result")
        var input = "Fish and chips", draft = "Original draft", effects = 0
        attempt.start(timeoutNanoseconds: 50_000_000, timedOut: { expired.fulfill() }) { token in
            started.fulfill(); _ = await backend.parse()
            attempt.publish(token) { input = ""; draft = "Late draft"; effects += 1 }
            returned.fulfill()
        }
        await fulfillment(of: [started, expired], timeout: 2)
        XCTAssertFalse(attempt.isRunning)
        backend.complete()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(input, "Fish and chips"); XCTAssertEqual(draft, "Original draft")
        XCTAssertEqual(effects, 0)
    }
}
