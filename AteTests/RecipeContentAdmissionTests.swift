import XCTest
@testable import Ate

@MainActor
final class RecipeContentAdmissionTests: XCTestCase {
    private func context() -> RecipeDiscoveryContext {
        .init(owner: "owner-a", saved: [.init(id: "saved", title: "Vegetable Soup")], cookedIDs: [], cookedRecipes: [])
    }
    private func stepsOnly() -> RecipeCard {
        var card = RecipeCard(title: "Tomato soup", servings: 0,
            steps: [.init(order: 1, instruction: "Simmer the tomatoes until soft. Serve hot.", timeSeconds: nil)],
            source: .appleIntelligence)
        card.suggestionDraft = true
        return card
    }
    func testExploreStepsOnlyFoodIsEditableAndCanBeExplicitlySaved() async throws {
        let session = RecipeDiscoverySession(), returned = expectation(description: "steps-only result")
        session.request(available: true, context: { self.context() }, generate: { _ in
            returned.fulfill(); return self.stepsOnly()
        })
        await fulfillment(of: [returned], timeout: 2)
        let card = try XCTUnwrap(session.suggestions.first)
        XCTAssertTrue(card.ingredients.isEmpty)
        XCTAssertTrue(card.isEditableDraft)
        XCTAssertFalse(card.steps.isEmpty)
        XCTAssertNil(session.message)
        XCTAssertTrue(session.savedIDs.isEmpty)
        var writes = 0
        XCTAssertTrue(session.save(card, context: { self.context() }) { _ in writes += 1; return true })
        XCTAssertEqual(writes, 1)
    }
    func testExploreNeitherContentNonFoodAndUntitledStayRejectedAtGenerationAndSave() async throws {
        var empty = stepsOnly(); empty.steps = []
        var memo = stepsOnly(); memo.steps[0].instruction = "Read the agenda at nine."
        var blankIngredient = memo; blankIngredient.ingredients = [.init(name: " \n", quantity: 0, unit: "")]
        var nonfood = stepsOnly(); nonfood.title = "plate"
        var untitled = stepsOnly(); untitled.title = "Untitled recipe"
        for invalid in [empty, memo, blankIngredient, nonfood, untitled] {
            let session = RecipeDiscoverySession(), returned = expectation(description: "rejected result")
            session.request(available: true, context: { self.context() }, generate: { _ in returned.fulfill(); return invalid })
            await fulfillment(of: [returned], timeout: 2)
            XCTAssertTrue(session.suggestions.isEmpty)
            XCTAssertNotNil(session.message)
            XCTAssertThrowsError(try OnDeviceBackend.validateImportedContent(invalid))
        }
        let session = RecipeDiscoverySession(), returned = expectation(description: "valid before edit")
        session.request(available: true, context: { self.context() }, generate: { _ in returned.fulfill(); return self.stepsOnly() })
        await fulfillment(of: [returned], timeout: 2)
        var edited = try XCTUnwrap(session.suggestions.first); edited.steps = []
        var writes = 0
        XCTAssertFalse(session.save(edited, context: { self.context() }) { _ in writes += 1; return true })
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(session.savedIDs.isEmpty)
    }
    func testRerunUsesSharedContentRuleForStepsOnlyAndRejectsNeitherContent() async throws {
        let current = stepsOnly()
        var calls = 0
        let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true }, createSuggestion: { _ in
            calls += 1; return self.stepsOnly()
        })
        let result = try await backend.rerunRecipe(current)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(result.ingredients.isEmpty)
        XCTAssertEqual(result.id, current.id)
        XCTAssertTrue(result.isEditableDraft)
        var invalid = current; invalid.steps = []
        let empty = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true }, createSuggestion: { _ in invalid })
        do { _ = try await empty.rerunRecipe(current); XCTFail("Neither-content output must fail") }
        catch { XCTAssertFalse(current.steps.isEmpty); XCTAssertTrue(current.ingredients.isEmpty) }
    }
}
