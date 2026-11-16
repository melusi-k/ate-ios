import XCTest
@testable import Ate

final class GeneratedIngredientDuplicateTests: XCTestCase {
    /// The visible fish-and-chips field assignment from build445,14Nov07:53.
    /// Keep it exactly: dedupe is not permission to fix invented/misparsed fields.
    private let lemon = Ingredient(name: "for serving", quantity: 1, unit: "lemon", notes: "sliced")

    func testExactGeneratedDuplicateKeepsFirstOccurrenceWithoutSummingOrFieldRewrite() {
        for source: RecipeSource in [.appleIntelligence, .photoGuess] {
            let fish = Ingredient(name: "fish fillets", quantity: 600, unit: "g", notes: "cleaned and cut into fillets")
            let potato = Ingredient(name: "potatoes", quantity: 300, unit: "g", notes: "sliced into chips")
            let card = RecipeCard(title: "Fish and chips", ingredients: [fish, lemon, potato, lemon], source: source)
            let normalized = RecipeLogic.normalize(card)
            XCTAssertEqual(normalized.ingredients, [fish, lemon, potato])
            XCTAssertEqual(normalized.ingredients[1].quantity, 1)
            XCTAssertEqual(normalized.ingredients[1].unit, "lemon")
            XCTAssertEqual(normalized.ingredients[1].name, "for serving")
            XCTAssertEqual(RecipeLogic.normalize(normalized), normalized, "Dedupe must be idempotent")
        }
    }

    func testDifferentCoatingGlazeAmountsNotesUnitsAndNamesRemainSeparate() {
        let coating = Ingredient(name: "brown sugar", quantity: 3, unit: "tbsp", notes: "for coating")
        let glaze = Ingredient(name: "brown sugar", quantity: 2, unit: "tbsp", notes: "for glazing")
        var noteOnly = coating; noteOnly.notes = "for glazing"
        var quantityOnly = coating; quantityOnly.quantity = 2
        var unitOnly = coating; unitOnly.unit = "tsp"
        var nameOnly = coating; nameOnly.name = "Brown sugar"
        var nilNote = coating; nilNote.notes = nil
        let rows = [coating, glaze, noteOnly, quantityOnly, unitOnly, nameOnly, nilNote]
        let card = RecipeCard(title: "Sticky ribs", ingredients: rows, source: .appleIntelligence)
        XCTAssertEqual(RecipeLogic.normalize(card).ingredients, rows)
    }

    func testManualAndImportedSourceRowsAreNotSilentlyDeduplicated() {
        for source: RecipeSource in [.manual, .jsonLD, .imported, .unknown, .mock] {
            let card = RecipeCard(title: "Source recipe", ingredients: [lemon, lemon], source: source)
            XCTAssertEqual(RecipeLogic.normalize(card).ingredients, [lemon, lemon], source.rawValue)
        }
    }

    func testFishChipOrderExampleDoesNotAddAGateOrHideLegitimateStepFourGaps() {
        let steps: [Step] = [
            .init(order: 1, instruction: "Season the fish fillets with salt and pepper", timeSeconds: nil),
            .init(order: 2, instruction: "Heat oil in a pan over medium heat and fry the fish fillets until golden brown, 3 min", timeSeconds: 180),
            .init(order: 3, instruction: "In another pan, fry the sliced potatoes in oil until golden, 5 min", timeSeconds: 300),
            .init(order: 4, instruction: "Boil the water with salt, then drain and rinse the potatoes to remove excess starch", timeSeconds: nil),
            .init(order: 5, instruction: "Serve the fish and chips hot, garnished with lemon slices", timeSeconds: nil),
            .init(order: 6, instruction: "Rest the fish fillets for 2 minutes before serving", timeSeconds: 120),
            .init(order: 7, instruction: "Serve the chips alongside the fish and lemon slices", timeSeconds: nil)]
        var card = RecipeCard(title: "Fish and chips", steps: steps, source: .appleIntelligence)
        card.aiNote = "Prep: 15 min. Potatoes are pre-boiled and drained before frying; this method is not a template for every dish."
        let normalized = RecipeLogic.normalize(card)
        XCTAssertEqual(normalized.steps.map(\.instruction), steps.map(\.instruction), "No automatic semantic reorder or deletion")
        let gaps = GeneratedStepQuality.issues(normalized)
        XCTAssertTrue(gaps.contains { $0.contains("Step 4") && $0.contains("cooking time") })
        XCTAssertTrue(gaps.contains { $0.contains("Step 4") && $0.contains("doneness cue") })
        XCTAssertTrue(RecipePrompt.instructions.contains("put that boil/drain before the fry"))
        XCTAssertTrue(RecipePrompt.instructions.contains("Do not impose pre-boiling"))
        XCTAssertTrue(RecipePrompt.instructions.contains("do not add repeated serve/rest/serve filler"))
    }
}
