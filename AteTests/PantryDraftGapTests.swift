import XCTest
@testable import Ate

final class PantryDraftGapTests: XCTestCase {
    /// Exact visible build445 draft,14Nov07:43. Title intentionally left unchanged:
    /// screenshots establish a mismatch, not the wording of the original source.
    static var screenshot: RecipeCard {
        var card = RecipeCard(title: "Sticky pork wings",
            description: "Pork wings coated in a sticky, spiced glaze using local ingredients.",
            servings: 6, timeMinutes: 150, tags: ["main", "south african", "glaze", "braise"],
            ingredients: [.init(name: "pork ribs", quantity: 1.2, unit: "kg", notes: "cleaned and cut into sections"),
                          .init(name: "brown sugar", quantity: 3, unit: "tbsp", notes: "for coating"),
                          .init(name: "smoked paprika", quantity: 2, unit: "tsp", notes: "mixed with sugar"),
                          .init(name: "garlic", quantity: 3, unit: "cloves", notes: "crushed"),
                          .init(name: "barbecue sauce", quantity: 125, unit: "ml", notes: "mixed with sugar and paprika"),
                          .init(name: "oil", quantity: 2, unit: "tbsp", notes: "for rubbing"),
                          .init(name: "salt", quantity: 1, unit: "tsp"),
                          .init(name: "pepper", quantity: 1, unit: "tsp")],
            steps: [.init(order: 1, instruction: "Rub the ribs with sugar, paprika and garlic. Wrap in foil and bake at 160°C until tender, 120 min. Unwrap, brush with sauce and roast at 220°C until sticky, 15 min.", timeSeconds: 135 * 60),
                    .init(order: 2, instruction: "Let the ribs rest for 5 minutes before serving.", timeSeconds: 5 * 60)],
            source: .appleIntelligence)
        card.aiConfidence = 0.85
        card.aiNote = "Prep: 10 min. The ribs are pre-baked in a low oven, then finished under high heat to create a sticky glaze. Some cooking times looked wrong and were corrected from the step text - check them before cooking."
        return card
    }

    func testExactRibsDraftDoesNotNeedPantryConfirmationOrFillerSteps() {
        let original = Self.screenshot
        let normalized = RecipeLogic.normalize(original)
        XCTAssertTrue(RecipeQuality.issues(normalized).isEmpty)
        XCTAssertEqual(RecipeQuality.shortfall(normalized), RecipeQuality.issues(normalized))
        XCTAssertFalse(RecipeQuality.needsInput(normalized))
        XCTAssertEqual(normalized.steps.count, 2)
        XCTAssertEqual(normalized.timeMinutes, 150, "140min cooking/rest plus10min explicit prep")
        XCTAssertEqual(normalized.title, original.title, "Do not guess what the source called this dish")
        XCTAssertEqual(normalized.ingredients, original.ingredients)
        XCTAssertThrowsError(try RecipeDraftRepair.instruction(for: normalized), "No quality repair is needed")
    }

    func testOnlyPlainPantryUnusedIngredientsAreExempt() {
        for name in ["salt", "pepper", "oil", " Salt "] {
            XCTAssertTrue(GeneratedStepQuality.isPlainPantrySeasoning(.init(name: name, quantity: 1, unit: "tsp")))
        }
        for name in ["lemon pepper", "chilli oil", "salted butter", "rice", "water", "bread"] {
            XCTAssertFalse(GeneratedStepQuality.isPlainPantrySeasoning(.init(name: name, quantity: 1, unit: "tsp")))
            var card = Self.screenshot
            card.ingredients.append(.init(name: name, quantity: 1, unit: "tsp"))
            XCTAssertTrue(GeneratedStepQuality.issues(card).contains { $0.contains(name) && $0.contains("never used") }, name)
        }
    }

    func testSubstantiveUnusedIngredientRemainsVisibleAndRepairableWithoutFiller() throws {
        var original = Self.screenshot
        original.ingredients.append(.init(name: "potatoes", quantity: 2, unit: "pcs"))
        let gaps = RecipeQuality.issues(original)
        XCTAssertEqual(RecipeQuality.shortfall(original), gaps)
        XCTAssertTrue(gaps.contains { $0.contains("potatoes") })
        var fixed = original
        fixed.steps[0].instruction += " Bake the potatoes alongside until tender."
        let repaired = try RecipeDraftRepair.accept(fixed, replacing: original)
        XCTAssertTrue(RecipeQuality.issues(repaired).isEmpty)
        XCTAssertEqual(repaired.steps.count, 2)
        XCTAssertEqual(repaired.ingredients, original.ingredients)
    }

    func testRepairErrorsDistinguishNoProgressFromNewProblemAndKeepStrictGuard() {
        var original = Self.screenshot
        original.ingredients.append(.init(name: "potatoes", quantity: 2, unit: "pcs"))
        XCTAssertThrowsError(try RecipeDraftRepair.accept(original, replacing: original)) {
            XCTAssertTrue($0.localizedDescription.contains("did not fix any"))
            XCTAssertTrue($0.localizedDescription.contains("unchanged"))
        }
        var traded = original
        traded.steps[0].instruction += " Bake potatoes until tender. Add butter."
        XCTAssertThrowsError(try RecipeDraftRepair.accept(traded, replacing: original)) {
            XCTAssertTrue($0.localizedDescription.contains("added a new problem"))
            XCTAssertTrue($0.localizedDescription.contains("butter"))
            XCTAssertTrue($0.localizedDescription.contains("unchanged"))
        }
        XCTAssertFalse(RecipeDraftRepair.automaticImproves(traded, over: original, labels: []))
    }
}
