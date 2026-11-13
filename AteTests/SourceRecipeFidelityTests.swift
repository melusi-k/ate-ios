import XCTest
@testable import Ate

final class SourceRecipeFidelityTests: XCTestCase {
    private let caption = RecipePromptTests.recipeCaption

    private func faithful() throws -> RecipeCard {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        return RecipeCard(title: "Chakalaka", ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: "Fry onion 5 minutes, add the rest and simmer 20 minutes.", timeSeconds: nil),
                    .init(order: 2, instruction: "Season to taste.", timeSeconds: nil)], source: .appleIntelligence)
    }

    func testF1ExplicitIngredientsRoundTripWithoutCreativeSubstitution() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        XCTAssertEqual(contract.ingredients.map(\.quantity), [2, 2, 3, 1, 2])
        XCTAssertEqual(contract.ingredients.map(\.unit), ["pcs", "pcs", "pcs", "tin", "tsp"])
        XCTAssertEqual(contract.ingredients.map(\.name), ["onions", "peppers", "carrots grated", "baked beans", "curry powder"])
        XCTAssertTrue(contract.issues(try faithful()).isEmpty)
        XCTAssertFalse(contract.text.contains("likes"))
        XCTAssertEqual(contract.method, "Fry onion 5 minutes, add the rest and simmer 20 minutes. Season to taste.")
    }

    func testF1HalvedOnionWrongCloveUnitDuplicateBeansAndInventedIngredientsAreRejected() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        var card = try faithful()
        card.ingredients[0].quantity = 1
        card.ingredients[2].unit = "cloves"
        card.ingredients += [.init(name: "beans", quantity: 400, unit: "g"),
                             .init(name: "oil", quantity: 2, unit: "tbsp"),
                             .init(name: "water", quantity: 0.5, unit: "l")]
        let failures = contract.issues(card)
        XCTAssertTrue(failures.contains { $0.contains("exactly the source") })
        XCTAssertTrue(failures.contains { $0.contains("onions") })
        XCTAssertTrue(failures.contains { $0.contains("carrots") })
    }

    func testDuplicateExactIngredientIsRejectedEvenIfListCountMatches() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        var card = try faithful()
        card.ingredients[0] = card.ingredients[3]
        XCTAssertFalse(contract.issues(card).isEmpty)
    }

    func testReorderedIngredientsDoNotPassAsVerbatimExtraction() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        var card = try faithful()
        card.ingredients.swapAt(0, 1)
        XCTAssertTrue(contract.issues(card).contains { $0.contains("ingredient order") })
    }

    func testWrittenTimesCannotBeShortenedReorderedOrAdded() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        for method in ["Fry onion 5 minutes then simmer 15 minutes.",
                       "Fry onion 20 minutes then simmer 5 minutes.",
                       "Fry onion 5 minutes then simmer 20 minutes and rest 10 minutes."] {
            var card = try faithful()
            card.steps = [.init(order: 1, instruction: method, timeSeconds: nil)]
            XCTAssertTrue(contract.issues(card).contains { $0.contains("written cooking times") })
        }
    }

    func testCompleteRangedDurationBoundsAndOrderMustSurvive() throws {
        for sourceTime in ["10-20 minutes", "10–20 min", "10 to 20 minutes", "1 hr 15 min"] {
            let source = "Stew. You need 2 onions, 3 carrots. Fry onion 5 minutes, then simmer " + sourceTime + ". Season to taste."
            let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(source))
            var card = RecipeCard(title: "Stew", ingredients: contract.ingredients,
                steps: [.init(order: 1, instruction: "Fry onion 5 minutes, then simmer " + sourceTime + ". Season to taste.", timeSeconds: nil)])
            XCTAssertTrue(contract.issues(card).isEmpty, sourceTime)
            for replacement in ["20 minutes", "1-20 minutes", "10-25 minutes", "75 minutes then 5 minutes"] {
                card.steps = [.init(order: 1, instruction: "Fry onion 5 minutes, then simmer " + replacement + ".", timeSeconds: nil)]
                XCTAssertTrue(contract.issues(card).contains { $0.contains("written cooking times") }, sourceTime + " -> " + replacement)
            }
        }
    }

    func testEquivalentDurationUnitsPreserveBoundsNotJustWrittenSuffix() throws {
        let source = "Stew. You need 2 onions, 3 carrots. Fry onion 5 minutes, then simmer 1-2 hours. Season to taste."
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(source))
        var card = RecipeCard(title: "Stew", ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: "Fry onion 5 min, then simmer 60-120 minutes. Season to taste.", timeSeconds: nil)])
        XCTAssertTrue(contract.issues(card).isEmpty)
        card.steps = [.init(order: 1, instruction: "Simmer 60-120 minutes then fry onion 5 min.", timeSeconds: nil)]
        XCTAssertTrue(contract.issues(card).contains { $0.contains("written cooking times") })
    }

    func testLimitedPrepAndPluralSeparationDoesNotInventAFoodAlias() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.inlineCaption(caption))
        var card = try faithful()
        card.ingredients[0].name = "onion"
        card.ingredients[2].name = "carrots"
        card.ingredients[2].notes = "grated"
        XCTAssertTrue(contract.issues(card).isEmpty)
        card.ingredients[2].name = "garlic"
        XCTAssertFalse(contract.issues(card).isEmpty)
    }

    func testUnsupportedStructureIsNotPartiallyCertified() {
        for text in ["vegan chakalaka for 6", "You need 2 onions, some carrots. Fry for 5 minutes.",
                     "You need 2 onions, 1 can beans", "Ingredients: 2 onions, 3 carrots. Fry 5 minutes."] {
            XCTAssertNil(SourceRecipeFidelity.inlineCaption(text), text)
        }
    }

    func testF2FullAndShortenedPromoRefusedWhileNamedDishAndFullRecipeRemainValid() {
        XCTAssertThrowsError(try SourceRecipeFidelity.rejectUngroundedText(RecipePromptTests.midrandAd))
        XCTAssertThrowsError(try SourceRecipeFidelity.rejectUngroundedText("191 likes, 6 comments - cookingwith_ritshidze_foods on September 17, 2025: \"Have you tried our food yet? Traditional food for delivery in Midrand and surrounding areas 🤩\""))
        XCTAssertNoThrow(try SourceRecipeFidelity.rejectUngroundedText(RecipePromptTests.mogoduMenu))
        XCTAssertNoThrow(try SourceRecipeFidelity.rejectUngroundedText(caption))
        XCTAssertNoThrow(try SourceRecipeFidelity.rejectUngroundedText("vegan chakalaka for 6"))
    }

    private final class Fallback: BackendService {
        var parses = 0
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard { parses += 1; return RecipeCard(title: "must not appear") }
        func publish(_ card: RecipeCard) async throws -> String { "unused" }
        func fetchShared(slug: String) async throws -> RecipeCard? { nil }
    }

    func testPastedF2RejectedBeforeBothModelAndFallbackNoRecipeOrPreview() async {
        for available in [false, true] {
            let fallback = Fallback()
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available })
            do {
                _ = try await backend.parseRecipe(.init(mode: .prompt, text: RecipePromptTests.midrandAd))
                XCTFail("promo must not create a card")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("doesn't look like a recipe"))
            }
            XCTAssertEqual(fallback.parses, 0)
        }
    }

    func testF1UnavailableModelDoesNotSubstituteDemoForExplicitSource() async {
        let fallback = Fallback()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        do {
            _ = try await backend.parseRecipe(.init(mode: .prompt, text: caption))
            XCTFail("source extraction must not become a demo")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No demo recipe was substituted")) }
        XCTAssertEqual(fallback.parses, 0)
    }
}
