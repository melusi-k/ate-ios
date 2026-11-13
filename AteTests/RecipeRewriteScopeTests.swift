import XCTest
@testable import Ate

final class RecipeRewriteScopeTests: XCTestCase {
    private func chakalaka() -> RecipeCard {
        RecipeCard(title: "Chakalaka", servings: 6, timeMinutes: 23,
            ingredients: [.init(name: "oil", quantity: 2, unit: "tbsp"), .init(name: "onion", quantity: 1, unit: "pcs"),
                          .init(name: "carrots", quantity: 2, unit: "pcs"), .init(name: "green pepper", quantity: 1, unit: "pcs"),
                          .init(name: "curry powder", quantity: 2, unit: "tsp"), .init(name: "tinned baked beans", quantity: 400, unit: "g")],
            steps: [.init(order: 1, instruction: "Saute onion in oil over medium heat until soft, 5 min.", timeSeconds: 300),
                    .init(order: 2, instruction: "Stir in carrots, green pepper and curry powder; fry 3 min.", timeSeconds: 180),
                    .init(order: 3, instruction: "Add beans and simmer uncovered until thick, 15 min.", timeSeconds: 900)], source: .appleIntelligence)
    }
    func testAlreadyPlantBasedExactVeganRequestIsNoOpNotQualityRepair() {
        XCTAssertNotNil(RecipeRewriteScope.noOpMessage(for: chakalaka(), request: "Make this vegan"))
        XCTAssertNil(RecipeRewriteScope.noOpMessage(for: chakalaka(), request: "Make this vegan and spicy"))
        var ambiguous = chakalaka()
        ambiguous.ingredients.append(.init(name: "stock", quantity: 100, unit: "ml"))
        XCTAssertNil(RecipeRewriteScope.noOpMessage(for: ambiguous, request: "Make this vegan"))
    }
    func testUnasked180CTemperatureSaltAndDrainDriftIsRefused() {
        let original = chakalaka()
        var candidate = original
        candidate.steps[0].instruction += " at 180C. Check for golden colour."
        candidate.ingredients[5].notes = "drain"
        XCTAssertThrowsError(try RecipeRewriteScope.accept(candidate, original: original, request: "Make this vegan"))
        XCTAssertTrue(GeneratedStepQuality.issues(candidate).contains { $0.contains("stovetop") })
    }
    func testBoundedVeganSubstitutionPreservesAllUnrelatedFields() throws {
        var original = chakalaka()
        original.ingredients = [.init(name: "butter", quantity: 1, unit: "tbsp"), .init(name: "onion", quantity: 1, unit: "pcs")]
        original.steps = [.init(order: 1, instruction: "Melt butter and add onion.", timeSeconds: nil)]
        var candidate = original
        candidate.ingredients[0].name = "vegan butter"
        candidate.steps[0].instruction = "Melt vegan butter and add onion."
        let result = try RecipeRewriteScope.accept(candidate, original: original, request: "Make this vegan")
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.title, original.title)
        XCTAssertEqual(result.timeMinutes, original.timeMinutes)
        XCTAssertEqual(result.aiNote, original.aiNote)
        XCTAssertEqual(result.ingredients[0].name, "vegan butter")
    }
    func testPartialSubstitutionCannotDeclareRemainingChickenVegan() {
        var original = chakalaka()
        original.ingredients = [.init(name: "butter", quantity: 1, unit: "tbsp"), .init(name: "chicken", quantity: 200, unit: "g")]
        original.steps = [.init(order: 1, instruction: "Melt butter and add chicken.", timeSeconds: nil)]
        var candidate = original
        candidate.ingredients[0].name = "vegan butter"
        candidate.steps[0].instruction = "Melt vegan butter and add chicken."
        XCTAssertThrowsError(try RecipeRewriteScope.accept(candidate, original: original, request: "Make this vegan"))
    }
    func testStepOnlyAnimalStockCannotSurviveAValidIngredientSubstitution() {
        var original = chakalaka()
        original.ingredients = [.init(name: "butter", quantity: 1, unit: "tbsp"), .init(name: "onion", quantity: 1, unit: "pcs")]
        original.steps = [.init(order: 1, instruction: "Melt butter, add onion and chicken stock.", timeSeconds: nil)]
        var candidate = original
        candidate.ingredients[0].name = "olive oil"
        candidate.steps[0].instruction = "Melt olive oil, add onion and chicken stock."
        XCTAssertThrowsError(try RecipeRewriteScope.accept(candidate, original: original, request: "Make this vegan"))
    }
    func testNoteOnlyAnimalCueRefusesAndApprovedPlantPhraseDoesNotMaskLaterAnimalCue() {
        var original = chakalaka()
        original.ingredients = [.init(name: "butter", quantity: 1, unit: "tbsp"), .init(name: "onion", quantity: 1, unit: "pcs", notes: "chicken stock for frying")]
        original.steps = [.init(order: 1, instruction: "Melt butter and add onion.", timeSeconds: nil)]
        var candidate = original
        candidate.ingredients[0].name = "vegan butter"
        candidate.steps[0].instruction = "Melt vegan butter and add onion."
        XCTAssertThrowsError(try RecipeRewriteScope.accept(candidate, original: original, request: "Make this vegan"))
        candidate.ingredients[1].notes = nil
        XCTAssertFalse(RecipeRewriteScope.hasResidualAnimalCue(candidate))
        candidate.steps[0].instruction += " Add milk."
        XCTAssertTrue(RecipeRewriteScope.hasResidualAnimalCue(candidate))
    }

    func testRealBackendNoOpReturnsByteEquivalentCardBeforeModelOrFallback() async throws {
        let original = chakalaka()
        let fallback = RewriteFallbackProbe()
        for available in [false, true] {
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available })
            let result = try await backend.parseRecipe(ParseRequest(mode: .rewrite, text: "Make this vegan", currentRecipe: original))
            XCTAssertEqual(result, original)
        }
        let calls = await fallback.count()
        XCTAssertEqual(calls, 0)
    }
    func testInternalOrMixedOvenStepIsNotFlaggedAsStovetopContradiction() {
        var card = chakalaka()
        card.steps[0].instruction = "Saute onion until soft, then bake in the oven at 180C for 10 min."
        XCTAssertFalse(GeneratedStepQuality.issues(card).contains { $0.contains("stovetop") })
    }
}
private actor RewriteFallbackProbe: BackendService {
    var calls = 0
    func count() -> Int { calls }
    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard { calls += 1; return RecipeCard(title: "Demo") }
    func publish(_ card: RecipeCard) async throws -> String { "unused" }
    func fetchShared(slug: String) async throws -> RecipeCard? { nil }
}
