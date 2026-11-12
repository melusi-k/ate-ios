import XCTest
@testable import Ate

final class GeneratedRecipeConsistencyTests: XCTestCase {
    /// Transcribed from Melusi's 11 Nov screenshot, not a claimed device eval pass.
    static var screenshot: RecipeCard {
        RecipeCard(title: "Mutton Bunny chow", description: "Slow-simmered mutton with onion and curry, served with pap.",
            servings: 6, timeMinutes: 198,
            ingredients: [.init(name: "mutton", quantity: 1.5, unit: "kg"),
                          .init(name: "onions", quantity: 2, unit: "pcs"),
                          .init(name: "garlic", quantity: 3, unit: "cloves"),
                          .init(name: "curry powder", quantity: 2, unit: "tsp"),
                          .init(name: "beef stock", quantity: 500, unit: "ml")],
            steps: [.init(order: 1, instruction: "Cover the mutton with salted water and simmer, covered, until tender", timeSeconds: 150 * 60),
                    .init(order: 2, instruction: "Fry the onion and garlic in oil over medium heat until golden", timeSeconds: 8 * 60),
                    .init(order: 3, instruction: "Stir in the curry powder, mutton and stock and simmer until thick", timeSeconds: 30 * 60)],
            source: .appleIntelligence)
    }

    func testScreenshotTriggersNamedRepairGapsNotSpeculativeSpiceRules() {
        let gaps = RecipeQuality.shortfall(Self.screenshot).joined(separator: " ")
        for term in ["bread", "hollow", "salt", "oil", "water", "extra 10 minutes"] {
            XCTAssertTrue(gaps.contains(term), term)
        }
        XCTAssertFalse(gaps.contains("cumin"), "No compulsory spice blend")
        XCTAssertFalse(gaps.contains("brown"), "Browning isn't universal")
    }

    func testExtraTenMinutesCanBeHonestPrepNotAnArithmeticFailure() {
        var c = Self.screenshot
        c.aiNote = "Prep: 10 min"
        let gaps = GeneratedRecipeConsistency.issues(c)
        XCTAssertFalse(gaps.contains { $0.contains("time") || $0.contains("minutes") })
        c.aiNote = "Prep: 15 min"
        XCTAssertTrue(GeneratedRecipeConsistency.issues(c).contains { $0.contains("Total time") })
        c.timeMinutes = 180
        XCTAssertTrue(GeneratedRecipeConsistency.issues(c).contains { $0.contains("Total time") })
    }

    func testStructuralAndStapleRepairPassesWithoutChangingDishIdentity() {
        var c = Self.screenshot
        c.aiNote = "Prep: 10 min"
        c.ingredients += [.init(name: "bread loaf", quantity: 1.5, unit: "pcs"),
                          .init(name: "salt", quantity: 1, unit: "tsp"),
                          .init(name: "oil", quantity: 2, unit: "tbsp"),
                          .init(name: "water", quantity: 1.5, unit: "l")]
        c.steps.append(.init(order: 4, instruction: "Hollow the bread portions and fill them with the mutton curry", timeSeconds: nil))
        XCTAssertTrue(GeneratedRecipeConsistency.issues(c).isEmpty)
    }

    func testNewChecksDoNotRewriteImportedOrManualSourceFacts() {
        for source: RecipeSource in [.manual, .jsonLD, .imported] {
            var c = Self.screenshot; c.source = source
            XCTAssertTrue(GeneratedRecipeConsistency.issues(c).isEmpty)
        }
    }

    func testBunnyChowIsNotKota() {
        let lookup = RecipePrompt.lookupRegionalDish("Mutton bunny chow")
        XCTAssertTrue(lookup.contains("Bunny chow"))
        XCTAssertTrue(lookup.contains("INSIDE hollowed bread"))
        XCTAssertFalse(lookup.contains("polony"))
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("kota").contains("polony"))
    }

    func testRepairPreservesNamedDishAndSourceOrder() {
        let p = RecipePrompt.retryInstruction(gaps: GeneratedRecipeConsistency.issues(Self.screenshot), visibleLabels: [])
        for term in ["Keep the named dish", "source facts", "ingredients", "retained or drained", "Prep: N min", "missing bread"] {
            XCTAssertTrue(p.contains(term), term)
        }
        XCTAssertTrue(RecipePrompt.instructions.contains("Preserve source order"))
        XCTAssertTrue(RecipePrompt.instructions.contains("salt, oil, water"))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    func testStructuredExampleDoesNotTeachTheScreenshotGaps() {
        var card = GenRecipe.exampleMogodu.card
        card.source = .appleIntelligence
        XCTAssertTrue(GeneratedRecipeConsistency.issues(card).isEmpty)
        XCTAssertFalse(card.description?.contains("pap") == true)
        XCTAssertTrue(card.steps[1].instruction.contains("drain"))
    }
    #endif
}
