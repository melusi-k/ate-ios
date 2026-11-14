import XCTest
@testable import Ate

final class LibraryProteinGroupingTests: XCTestCase {
    private func recipe(_ ingredients: [Ingredient], title: String = "Sticky Ribs and wings") -> RecipeCard {
        RecipeCard(id: "mixed-ribs", title: title, tags: ["main", "chicken"], ingredients: ingredients)
    }
    private func ingredient(_ name: String, _ quantity: Double, _ unit: String) -> Ingredient {
        .init(name: name, quantity: quantity, unit: unit)
    }

    func testOwnersRibsAndWingsAppearUnderPorkNotChickenAndPorkCollectionExists() {
        let ribs = recipe([ingredient("pork ribs", 1, "kg"), ingredient("chicken wings", 800, "g"),
                           ingredient("brown sugar", 3, "tbsp")])
        var layout = LibraryLayout(); layout.group = .mainIngredient
        let sections = layout.sections([ribs])
        XCTAssertEqual(sections.map(\.title), ["Pork"])
        XCTAssertEqual(sections.first?.recipes.map(\.id), [ribs.id])
        XCTAssertEqual(IngredientTags.main(for: ribs), "pork")
        XCTAssertTrue(IngredientTags.collections(in: [ribs]).contains("pork"))
        XCTAssertTrue(IngredientTags.available(in: [ribs]).contains("pork"))
        XCTAssertTrue(IngredientTags.tags(for: ribs).isSuperset(of: ["pork", "chicken"]))
        var filter = RecipeFilter(); filter.collection = .ingredient("pork")
        XCTAssertEqual(filter.apply([ribs]).map(\.id), [ribs.id])
    }

    func testPorkCutsClassifyAsPorkRegardlessOfRecipeTitleOrGeneratedTags() {
        for cut in ["pork ribs", "pork belly", "bacon", "pork chops", "pork shoulder", "pork mince", "baby back ribs", "spare ribs", "spareribs", "gammon", "pancetta"] {
            let card = recipe([ingredient(cut, 500, "g")], title: "Dinner")
            XCTAssertEqual(IngredientTags.main(for: card), "pork", cut)
            XCTAssertTrue(IngredientTags.collections(in: [card]).contains("pork"), cut)
        }
    }

    func testLargestComparableProteinWinsEvenWhenChickenIsFirst() {
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("chicken wings", 800, "g"), ingredient("pork ribs", 1.2, "kg")])), "pork")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork ribs", 800, "g"), ingredient("chicken wings", 1.2, "kg")])), "chicken")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork ribs", 1, "lb"), ingredient("chicken wings", 300, "g")])), "pork")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork belly", 8, "oz"), ingredient("beef", 0.2, "kg")])), "pork")
    }

    func testAggregatesProteinAmountsAndTieKeepsLeadingProtein() {
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("chicken", 700, "g"), ingredient("pork belly", 0.5, "kg"), ingredient("bacon", 250, "g")])), "pork")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork ribs", 1, "kg"), ingredient("chicken wings", 1000, "g")])), "pork")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("chicken wings", 1000, "g"), ingredient("pork ribs", 1, "kg")])), "chicken")
    }

    func testUnknownOrIncompatibleQuantitiesKeepFirstProteinWithoutInventingWeights() {
        for quantity in [0, -1, .nan, .infinity] {
            XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork ribs", quantity, "kg"), ingredient("chicken wings", 800, "g")])), "pork")
        }
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork ribs", 1, "rack"), ingredient("chicken wings", 800, "g")])), "pork")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("chicken wings", 6, "pcs"), ingredient("pork ribs", 1, "kg")])), "chicken")
        XCTAssertEqual(IngredientTags.main(for: recipe([ingredient("pork chops", 4, "pcs"), ingredient("chicken thighs", 2, "pcs")])), "pork")
    }

    func testNamedSpeciesBeatAmbiguousCutsAndBareRibsAreNotAssumedPork() {
        for (name, expected) in [("beef ribs", "beef"), ("lamb ribs", "lamb"), ("beef sausage", "beef"), ("pork mince", "pork")] {
            let card = recipe([ingredient(name, 1, "kg")], title: "Dinner")
            XCTAssertEqual(IngredientTags.main(for: card), expected)
            XCTAssertFalse(IngredientTags.tags(for: card).contains("chicken"))
        }
        XCTAssertNotEqual(IngredientTags.main(for: recipe([ingredient("ribs", 1, "kg")], title: "Ribs")), "pork")
    }

    func testGroupingDoesNotRewriteAnySavedRecipeFacts() {
        let card = recipe([ingredient("pork ribs", 1, "kg"), ingredient("chicken wings", 800, "g")])
        let original = card
        var layout = LibraryLayout(); layout.group = .mainIngredient
        XCTAssertEqual(layout.sections([card]).first?.recipes.first, original)
        XCTAssertEqual(card, original)
        XCTAssertEqual(card.tags, ["main", "chicken"], "An old generated tag does not require rewriting saved source facts")
    }

    func testPromptNamesSpeciesAndKeepsActualSourceQuantities() {
        XCTAssertTrue(RecipePrompt.instructions.contains("pork ribs, pork belly, bacon, pork chops"))
        XCTAssertTrue(RecipePrompt.instructions.contains("largest comparable quantity"))
        XCTAssertTrue(RecipePrompt.instructions.contains("do not guess weights for counted pieces"))
    }
}
