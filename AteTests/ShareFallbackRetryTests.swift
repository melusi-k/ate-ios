import XCTest
@testable import Ate

final class ShareFallbackRetryTests: XCTestCase {
    func testRetryIsQueuedUntilDismissalAndConsumedOnce() {
        var state = ShareFallbackRetry()
        let recipe = RecipeCard(id: "retained", title: "Keep this stew")
        state.request(recipe)
        guard case .retry(let result) = state.presentationDidDismiss() else { return XCTFail("Missing queued retry") }
        XCTAssertEqual(result.id, recipe.id)
        XCTAssertEqual(result.title, recipe.title)
        XCTAssertNil(state.presentationDidDismiss(), "Duplicate dismissal must not duplicate publish")
    }

    func testRepeatedImmediateFailureCanOfferAnotherRetry() {
        var state = ShareFallbackRetry()
        let recipe = RecipeCard(id: "retained", title: "Keep this stew")
        for _ in 0..<3 {
            state.request(recipe)
            guard case .retry(let result) = state.presentationDidDismiss() else { return XCTFail("Retry lost") }
            XCTAssertEqual(result.id, "retained")
            XCTAssertNil(state.presentationDidDismiss())
            // Immediate failure reopens the fallback only AFTER this callback.
        }
    }

    func testTextFallbackAlsoWaitsForDismissalAndNeverPublishes() {
        var state = ShareFallbackRetry()
        state.requestText(RecipeCard(id: "text", title: "Retained"))
        guard case .text(let recipe) = state.presentationDidDismiss() else { return XCTFail("Text action lost or became publish") }
        XCTAssertEqual(recipe.id, "text")
        XCTAssertNil(state.presentationDidDismiss())
    }

    func testCancelOrInteractiveDismissalDoesNotRetry() {
        var state = ShareFallbackRetry()
        XCTAssertNil(state.presentationDidDismiss())
    }
}
