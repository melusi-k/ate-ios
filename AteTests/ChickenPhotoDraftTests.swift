import XCTest
@testable import Ate

final class ChickenPhotoDraftTests: XCTestCase {
    func testNamedPhotoGroundingPreservesDishAndKeepsMethodOutOfNotesOnly() {
        let prompt = RecipePrompt.photo(dish: "chicken au poivre", labels: ["chicken"], ocr: "chicken au poivre")
        XCTAssertTrue(prompt.contains("A photo shows this dish: chicken au poivre"))
        XCTAssertTrue(prompt.contains(RecipePrompt.photoGrounding))
        for phrase in ["Keep the source dish name", "omit unsupported cuisine claims", "not only the note", "Browning alone"] {
            XCTAssertTrue(prompt.contains(phrase))
        }
    }

    /// Visible build445 photo-guess card,15Nov08:37. Do not invent the absent
    /// finishing method, missing sauce ingredients or a sprig/clove measurement.
    func testChickenAuPoivrePhotoDraftStaysIncompleteAfterSafeFieldNormalization() {
        var raw = RecipeCard(title: "Chicken au Poivre",
            description: "Traditional South African chicken cooked with pepper and herbs.",
            servings: 4, timeMinutes: 17, tags: ["main", "south african"],
            ingredients: [.init(name: "chicken pieces", quantity: 1.2, unit: "kg", notes: "cleaned and cut into chunks"),
                          .init(name: "oil", quantity: 2, unit: "tbsp", notes: "for searing"),
                          .init(name: "diced", quantity: 1, unit: "onion", notes: "chopped"),
                          .init(name: "thyme", quantity: 1, unit: "herb", notes: "fresh, chopped"),
                          .init(name: "crushed", quantity: 1, unit: "garlic", notes: "crushed"),
                          .init(name: "black pepper", quantity: 1.5, unit: "tsp", notes: "crushed"),
                          .init(name: "water", quantity: 200, unit: "ml", notes: "for the pepper infusion")],
            steps: [.init(order: 1, instruction: "Sear the chicken pieces in oil over medium heat until browned, 5 min at 180°C.", timeSeconds: 300)],
            source: .photoGuess)
        raw.aiConfidence = 0.6
        raw.aiNote = "Prep: 12 min. The pepper is infused in water before adding to the chicken; this method is not a template for every dish."
        let normalized = RecipeLogic.normalize(raw)
        XCTAssertEqual(normalized.title, raw.title)
        XCTAssertEqual(normalized.description, raw.description, "A validator must not silently rewrite uncertain source claims")
        XCTAssertEqual(normalized.timeMinutes, 17, "5min plus12prep is arithmetic, not proof of a complete method")
        XCTAssertEqual(normalized.steps, raw.steps)
        XCTAssertEqual(normalized.aiConfidence, 0.6)
        XCTAssertEqual(normalized.ingredients[2].name, "onion")
        XCTAssertEqual(normalized.ingredients[2].unit, "pcs")
        XCTAssertEqual(normalized.ingredients[4].name, "garlic")
        XCTAssertEqual(normalized.ingredients[4].unit, "pcs", "Never invent cloves from an ambiguous count")
        XCTAssertEqual(normalized.ingredients[4].notes, "crushed")
        XCTAssertEqual(normalized.ingredients[3].unit, "herb", "Keep invalid measure for visible correction")
        let gaps = RecipeQuality.issues(normalized)
        XCTAssertTrue(gaps.contains { $0.contains("stops after browning") })
        XCTAssertTrue(gaps.contains { $0.contains("herb is not a measurement") })
        XCTAssertTrue(gaps.contains { $0.contains("black pepper") && $0.contains("never used") })
        XCTAssertTrue(gaps.contains { $0.contains("water") && $0.contains("never used") })
        XCTAssertTrue(RecipeQuality.needsInput(normalized))
        XCTAssertEqual(RecipeQuality.shortfall(normalized), gaps)
        XCTAssertNoThrow(try RecipeDraftRepair.instruction(for: normalized))
        XCTAssertThrowsError(try RecipeDraftRepair.accept(normalized, replacing: normalized),
                             "Identical incomplete method is not a repair")
    }
}
