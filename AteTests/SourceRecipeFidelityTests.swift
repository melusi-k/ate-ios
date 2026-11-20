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
                     "You need 2 onions, 1 can beans", "Ingredients: 2 onions, 3 carrots. Fry 5 minutes.",
                     // A parenthesis can hide an unmeasured item inside a measured part.
                     "You need 1 kg beef tripe, 2 onions (salt to taste). Simmer 150 minutes, season.",
                     "You need 1 kg beef tripe, 2 onions, salt to taste. Simmer 150 minutes, season.",
                     "You need 1 kg beef tripe, 2 onions (salt). Simmer 150 minutes, season.",
                     "You need 1 kg beef tripe, 2 onions, salt. Simmer 150 minutes, season."] {
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

    // A recipe web page after htmlToText: one collapsed line, explicit sections.
    // A real page whose htmlToText output kept its list/line-break boundaries: one item
    // per line, exactly what the parser will certify.
    private let tripePage = "Home Recipes About Mogodu Serves 6 Prep: 15 min Cook: 3 h Ingredients\n1.2 kg beef tripe, cleaned and cut into strips\n2 onions, chopped\n3 cloves garlic, crushed\n2 tsp curry powder\n500 ml beef stock\n1.5 l water\n1 tsp salt\n2 tbsp oil\nMethod\nCut the cleaned tripe into strips, chop the onions and crush the garlic. Cover the tripe with the water and salt. Simmer covered until tender, about 150 minutes, then drain the cooking liquid. Fry the onion and garlic in the oil over medium heat until golden, 8 minutes. Stir in the curry powder without burning it, then add the drained tripe and stock and simmer gently until thick and the tripe is tender. Divide the tripe and sauce between six bowls and serve hot. Notes Best with pap."

    private let pastedTripeRecipe = "Mogodu\nServes 6\n\nIngredients\n1.2 kg beef tripe, cleaned and cut into strips\n2 onions, chopped\n3 cloves garlic, crushed\n2 tsp curry powder\n500 ml beef stock\n1.5 l water\n1 tsp salt\n2 tbsp oil\n\nMethod\n1. Cut the cleaned tripe into strips, chop the onions and crush the garlic.\n2. Cover with the water and salt. Simmer covered until tender, about 150 minutes, then drain.\n3. Fry the onion and garlic in the oil until golden, 8 minutes.\n4. Stir in the curry powder, add the drained tripe and stock and simmer gently until thick.\n5. Divide between six bowls and serve hot."

    private func faithfulTripe() throws -> RecipeCard {
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(tripePage))
        var card = RecipeCard(title: "Mogodu", ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: "Cut the cleaned tripe into strips, chop the onions and crush the garlic.", timeSeconds: nil),
                    .init(order: 2, instruction: "Cover the tripe with the water and salt. Simmer covered until tender, about 150 minutes, then drain the cooking liquid.", timeSeconds: nil),
                    .init(order: 3, instruction: "Fry the onion and garlic in the oil over medium heat until golden, 8 minutes.", timeSeconds: nil),
                    .init(order: 4, instruction: "Stir in the curry powder without burning it, then add the drained tripe and stock and simmer gently until thick and the tripe is tender.", timeSeconds: nil),
                    .init(order: 5, instruction: "Divide the tripe and sauce between six bowls and serve hot.", timeSeconds: nil)], source: .appleIntelligence)
        card.servings = 6
        return card
    }

    func testStructuredPageRoundTripsItsOwnFactsWithoutCreativeSubstitution() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(tripePage))
        XCTAssertEqual(contract.dishes, ["Mogodu / ulusu (tripe)"])
        XCTAssertEqual(contract.ingredients.map(\.quantity), [1.2, 2, 3, 2, 500, 1.5, 1, 2])
        XCTAssertEqual(contract.ingredients.map(\.unit), ["kg", "pcs", "cloves", "tsp", "ml", "l", "tsp", "tbsp"])
        XCTAssertEqual(contract.ingredients.map(\.name), ["beef tripe", "onions", "garlic", "curry powder", "beef stock", "water", "salt", "oil"])
        XCTAssertTrue(contract.issues(try faithfulTripe()).isEmpty)
    }

    func testPrepTailsOnTheRealTripePageStayVerifiable() throws {
        // The tripe page's comma tails are all preparation syntax: they survive the
        // whitelist and stay attached to their measured items as notes.
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(tripePage))
        XCTAssertEqual(contract.ingredients.count, 8)
        XCTAssertEqual(contract.ingredients[0].notes, "cleaned and cut into strips")
        XCTAssertEqual(contract.ingredients[1].notes, "chopped")
        XCTAssertEqual(contract.ingredients[2].notes, "crushed")
        XCTAssertTrue(contract.issues(try faithfulTripe()).isEmpty)
        // Whitelist shape: prep words chain with spaces, commas or "and" only.
        XCTAssertTrue(SourceRecipeFidelity.isPrepOnly("cleaned and cut into strips"))
        XCTAssertTrue(SourceRecipeFidelity.isPrepOnly("peeled, chopped"))
        XCTAssertTrue(SourceRecipeFidelity.isPrepOnly("grated"))
        XCTAssertFalse(SourceRecipeFidelity.isPrepOnly("salt"))
        XCTAssertFalse(SourceRecipeFidelity.isPrepOnly("finely chopped"))
        XCTAssertFalse(SourceRecipeFidelity.isPrepOnly("For the sauce"))
        XCTAssertFalse(SourceRecipeFidelity.isPrepOnly("chopped and salt"))
        XCTAssertFalse(SourceRecipeFidelity.isPrepOnly(""))
    }

    func testHTMLListAndBreakBoundariesLetARealPageCertify() throws {
        // htmlToText preserves <li> and <br> as line boundaries, so a real recipe page
        // keeps one item per line and verifies; the tripe page fixture is exactly that
        // output shape.
        let html = "<html><head><title>Mogodu</title></head><body><h1>Mogodu</h1><p>Serves 6</p><h2>Ingredients</h2><ul><li>1.2 kg beef tripe, cleaned and cut into strips</li><li>2 onions, chopped</li><li>3 cloves garlic, crushed</li><li>2 tsp curry powder</li><li>500 ml beef stock</li><li>1.5 l water</li><li>1 tsp salt</li><li>2 tbsp oil</li></ul><h2>Method</h2><p>Cut the cleaned tripe into strips. Cover with the water and salt. Simmer covered until tender, about 150 minutes, then drain. Fry the onion and garlic in the oil until golden, 8 minutes. Stir in the curry powder, add the drained tripe and stock and simmer gently until thick. Divide between six bowls and serve hot.</p></body></html>"
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(OnDeviceBackend.htmlToText(html)))
        XCTAssertEqual(contract.ingredients.count, 8)
        XCTAssertEqual(contract.ingredients.map(\.name), ["beef tripe", "onions", "garlic", "curry powder", "beef stock", "water", "salt", "oil"])
        XCTAssertTrue(contract.issues(try faithfulTripe()).isEmpty)
    }

    func testOwnLineUnitlessItemsStaySupported() throws {
        // One measured item per line needs no unit and no tail: the line break is the
        // explicit boundary.
        let pasted = "Mogodu\nIngredients\n1 kg beef tripe\n2 onions\nMethod\nSimmer 150 minutes, fry 5 minutes, season."
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(pasted))
        XCTAssertEqual(contract.ingredients.map(\.name), ["beef tripe", "onions"])
        XCTAssertEqual(contract.ingredients.map(\.unit), ["kg", "pcs"])
    }

    func testStructuredPageRejectsInventedDishAndRenamedIngredients() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(tripePage))
        var card = try faithfulTripe()
        card.title = "Creamy Paprika Beef Pasta"
        card.ingredients[0].name = "beef ribs"
        let failures = contract.issues(card)
        XCTAssertTrue(failures.contains { $0.contains("Name the dish the source names") })
        XCTAssertTrue(failures.contains { $0.contains("paprika") && $0.contains("never mentions") })
        XCTAssertTrue(failures.contains { $0.contains("pasta") && $0.contains("never mentions") })
        XCTAssertTrue(failures.contains { $0.contains("Preserve the source ingredient: beef tripe") })
        XCTAssertTrue(failures.contains { $0.contains("order and names") })
    }

    func testStructuredPageTimesCannotBeShortenedReorderedDroppedOrInvented() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(tripePage))
        var shortened = try faithfulTripe()
        shortened.steps[1].instruction = "Cover the tripe with the water and salt. Simmer covered until tender, about 15 minutes, then drain the cooking liquid."
        XCTAssertTrue(contract.issues(shortened).contains { $0.contains("written cooking times") })
        var reordered = try faithfulTripe()
        reordered.steps[1].instruction = "Fry the onion and garlic in the oil over medium heat until golden, 8 minutes."
        reordered.steps[2].instruction = "Cover the tripe with the water and salt. Simmer covered until tender, about 150 minutes, then drain the cooking liquid."
        XCTAssertTrue(contract.issues(reordered).contains { $0.contains("written cooking times") })
        var dropped = try faithfulTripe()
        dropped.steps[2].instruction = "Fry the onion and garlic in the oil over medium heat until golden."
        XCTAssertTrue(contract.issues(dropped).contains { $0.contains("written cooking times") })
        var invented = try faithfulTripe()
        invented.steps[3].instruction += " Simmer 30 minutes."
        XCTAssertTrue(contract.issues(invented).contains { $0.contains("written cooking times") })
    }

    func testTitleFoodNounsMustAppearInSourceEvenWithoutKnownDish() throws {
        let page = "Weekday Chicken Alfredo Serves 4 Ingredients\n500 g chicken breast\n250 ml fresh cream\n300 g fettuccine\nMethod\nFry the chicken for 10 minutes. Add the cream and pasta and simmer for 5 minutes. Season to taste."
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(page))
        XCTAssertTrue(contract.dishes.isEmpty)
        var card = RecipeCard(title: "Chicken Alfredo", ingredients: contract.ingredients,
            steps: [.init(order: 1, instruction: "Fry the chicken for 10 minutes.", timeSeconds: nil),
                    .init(order: 2, instruction: "Add the cream and pasta and simmer for 5 minutes. Season to taste.", timeSeconds: nil)], source: .appleIntelligence)
        XCTAssertTrue(contract.issues(card).isEmpty)
        card.title = "Pork Alfredo"
        XCTAssertTrue(contract.issues(card).contains { $0.contains("pork") && $0.contains("never mentions") })
    }

    func testAmbiguousPageStructureIsNotPartiallyCertified() {
        for text in ["Mogodu Ingredients For the sauce: 1.2 kg beef tripe 2 onions Method Simmer 150 minutes, fry 5 minutes, season.",
                     // An unmeasured amount absorbed into the previous item's name is not verified.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions salt to taste Method Simmer 150 minutes, fry 5 minutes, season.",
                     // An interior heading after a measured item is not part of its name.
                     "Mogodu Ingredients 2 onions For the sauce: 500 g tomatoes Method Fry 5 minutes, simmer 10 minutes, season.",
                     "Mogodu Ingredients 2 onions For the sauce 500 g tomatoes Method Fry 5 minutes, simmer 10 minutes, season.",
                     // A comma tail moves an unmeasured item into the parsed notes, past a
                     // name-only check: tails are prep-word whitelist, not blacklist.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions, salt to taste Method Simmer 150 minutes, fry 5 minutes, season.",
                     // An interior heading after a comma hides in the notes the same way.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions, For the sauce: 500 g tomatoes Method Fry 5 minutes, simmer 10 minutes, season.",
                     // An unmeasured item inside parentheses hides in the notes too.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions (salt to taste) Method Simmer 150 minutes, fry 5 minutes, season.",
                     // A bare unmeasured item as a comma tail: no blacklist words at all.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions, salt Method Simmer 150 minutes, fry 5 minutes, season.",
                     // A bare unmeasured item inside parentheses.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions (salt) Method Simmer 150 minutes, fry 5 minutes, season.",
                     // An interior heading after a comma with no colon and no blacklist word.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions, For the sauce 500 g tomatoes Method Fry 5 minutes, simmer 10 minutes, season.",
                     // Separate lines are the defensible boundary for pasted recipes:
                     // any unmeasured line makes the whole recipe unverifiable.
                     "Mogodu\nIngredients\n1 kg beef tripe\n2 onions\nsalt\nMethod\nSimmer 150 minutes, fry 5 minutes, season.",
                     "Mogodu\nIngredients\n1 kg beef tripe\nonions and salt\nMethod\nSimmer 150 minutes, fry 5 minutes, season.",
                     // One collapsed line has no defensible boundary between a name and
                     // an unmeasured neighbour: ALL multi-item shared lines are refused.
                     "Mogodu Ingredients 1 kg beef tripe 2 onions salt Method Simmer 150 minutes, fry 5 minutes, season.",
                     "Mogodu Ingredients 1 kg beef tripe 2 onions Method Simmer 150 minutes, fry 5 minutes, season.",
                     // The exact reported repro: a recognized unit does not mark where a
                     // name ends, and a prep tail does not rescue a shared line either.
                     "Mogodu Ingredients 1 kg beef tripe 500 ml water salt Method Simmer 150 minutes, fry 5 minutes, season.",
                     "Mogodu Ingredients 1 kg beef tripe 500 ml water salt, chopped Method Simmer 150 minutes, fry 5 minutes, season.",
                     "Mogodu Ingredients 1.2 kg beef tripe 2 onions Method Simmer 150 minutes, season. Ingredients 500 g rice 1 tsp salt Method Boil 20 minutes, stir.",
                     "Serves 6 Ingredients Method Simmer 5 minutes, stir, season."] {
            XCTAssertNil(SourceRecipeFidelity.structuredRecipe(text), text)
        }
    }

    func testRecognizableButUnverifiableStructureIsDistinguishedFromNoStructure() throws {
        let unverifiable = "Mogodu Ingredients 1 kg beef tripe 2 onions salt to taste Method Simmer 150 minutes, fry 5 minutes, season."
        XCTAssertNil(SourceRecipeFidelity.structuredRecipe(unverifiable))
        XCTAssertTrue(SourceRecipeFidelity.claimsStructuredRecipe(unverifiable))
        guard case .unverifiable = SourceRecipeFidelity.extraction(unverifiable) else {
            return XCTFail("recognizable-but-unverifiable must be refused, never creative generation")
        }
        XCTAssertFalse(SourceRecipeFidelity.claimsStructuredRecipe("chicken pasta"))
        guard case .none = SourceRecipeFidelity.extraction("chicken pasta") else {
            return XCTFail("no structure stays on the creative path")
        }
        // A recognizable caption that fails certification is unverifiable, never .none:
        // it must not fall through to creative generation or a demo substitute.
        let badCaption = "You need 1 kg beef tripe, 2 onions (salt). Simmer 150 minutes, season."
        XCTAssertNil(SourceRecipeFidelity.inlineCaption(badCaption))
        XCTAssertTrue(SourceRecipeFidelity.claimsInlineCaption(badCaption))
        guard case .unverifiable = SourceRecipeFidelity.extraction(badCaption) else {
            return XCTFail("recognizable-but-unverifiable caption must be refused")
        }
        XCTAssertFalse(SourceRecipeFidelity.claimsInlineCaption("chicken pasta"))
        XCTAssertFalse(SourceRecipeFidelity.claimsStructuredRecipe(RecipePromptTests.mogoduMenu))
        guard case .verified = SourceRecipeFidelity.extraction(tripePage) else {
            return XCTFail("verified structure binds generation")
        }
        guard case .verified = SourceRecipeFidelity.extraction(caption) else {
            return XCTFail("the you-need caption keeps its verified contract")
        }
    }

    func testStructuredCaptionIsRecognizedByTheSharedPreModelStep() throws {
        // A caption with real line breaks has explicit item boundaries and verifies.
        let structuredCaption = "88 likes, 3 comments - kasi_kitchen on 1 October 2026: \"Mogodu recipe Serves 6\nIngredients\n1.2 kg beef tripe, cleaned and cut into strips\n2 onions, chopped\n3 cloves garlic, crushed\n2 tsp curry powder\n500 ml beef stock\n1.5 l water\n1 tsp salt\n2 tbsp oil\nMethod\nCut the cleaned tripe into strips, chop the onions and crush the garlic. Cover the tripe with the water and salt. Simmer covered until tender, about 150 minutes, then drain the cooking liquid. Fry the onion and garlic in the oil over medium heat until golden, 8 minutes. Stir in the curry powder without burning it, then add the drained tripe and stock and simmer gently until thick and the tripe is tender. Divide the tripe and sauce between six bowls and serve hot.\""
        guard case .verified(let contract) = SourceRecipeFidelity.extraction(structuredCaption) else {
            return XCTFail("a structured caption must bind before the model runs")
        }
        XCTAssertTrue(contract.issues(try faithfulTripe()).isEmpty)
        // The same caption collapsed onto one line has no defensible item boundaries:
        // unverifiable, refused honestly, never generated or demoed.
        let collapsed = structuredCaption.replacingOccurrences(of: "\n", with: " ")
        XCTAssertNil(SourceRecipeFidelity.structuredRecipe(collapsed))
        guard case .unverifiable = SourceRecipeFidelity.extraction(collapsed) else {
            return XCTFail("a collapsed multi-item caption must fail closed")
        }
    }

    func testPastedMultilineRecipeParsesLikeAPage() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(pastedTripeRecipe))
        XCTAssertEqual(contract.ingredients.count, 8)
        XCTAssertTrue(contract.issues(try faithfulTripe()).isEmpty)
    }

    func testPastedStructuredRecipeDoesNotSubstituteDemoWhenModelIsUnavailable() async throws {
        let fallback = Fallback()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { XCTFail("Paste must not ask model availability"); return false })
        let card = try await backend.parseRecipe(.init(mode: .prompt, text: pastedTripeRecipe))
        XCTAssertEqual(card.source, .imported)
        XCTAssertEqual(card.servings, 6)
        XCTAssertEqual(card.ingredients, try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(pastedTripeRecipe)).ingredients)
        XCTAssertNotNil(card.pastedSource)
        XCTAssertEqual(fallback.parses, 0)
    }

    // Superseded admission behavior: contracts remain strict evidence for the
    // fast path, but incomplete sources now open as editable source drafts.
    func testUnverifiableStructureFailsClosedBeforeCreativeGenerationOrDemo() async throws {
        let page = "<html><body><h1>Mogodu</h1><p>Serves 6</p><h2>Ingredients</h2><p>1 kg beef tripe 2 onions salt to taste</p><h2>Method</h2><p>Simmer 150 minutes, fry 5 minutes, season.</p></body></html>"
        for available in [false, true] {
            let fallback = Fallback()
            var fetches = 0, calls = 0
            let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in fetches += 1; return page },
                modelAvailable: { available }, selectSourceLines: { raw in calls += 1; return SourceDraftImport.selection(raw) })
            let card = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/mogodu"))
            XCTAssertEqual(card.source, .imported)
            XCTAssertNotNil(card.sourceDraft)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(calls, available ? 1 : 0)
            XCTAssertEqual(fetches, 1)
            XCTAssertEqual(fallback.parses, 0)
        }
    }

    func testUnverifiableCaptionFailsClosedBeforeCreativeGenerationOrDemo() async throws {
        let badCaption = "You need 1 kg beef tripe, 2 onions (salt). Simmer 150 minutes, season."
        for available in [false, true] {
            let fallback = Fallback()
            var calls = 0
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available }, selectSourceLines: { raw in
                calls += 1; return SourceDraftImport.selection(raw)
            })
            let card = try await backend.parseRecipe(.init(mode: .prompt, text: badCaption))
            XCTAssertEqual(card.sourceDraft?.text, badCaption)
            XCTAssertEqual(card.servings, 0)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(calls, available ? 1 : 0)
            XCTAssertEqual(fallback.parses, 0)
        }
    }

    func testStructuredPageDoesNotSubstituteDemoWhenModelIsUnavailable() async throws {
        let fallback = Fallback()
        var fetches = 0
        let page = "<html><head><title>Mogodu</title></head><body><h1>Mogodu</h1><p>Serves 6</p><h2>Ingredients</h2><p>1.2 kg beef tripe, cleaned and cut into strips<br>2 onions, chopped<br>3 cloves garlic, crushed<br>2 tsp curry powder<br>500 ml beef stock<br>1.5 l water<br>1 tsp salt<br>2 tbsp oil</p><h2>Method</h2><p>Cut the cleaned tripe into strips. Cover with the water and salt. Simmer covered until tender, about 150 minutes, then drain. Fry the onion and garlic in the oil until golden, 8 minutes. Stir in the curry powder, add the drained tripe and stock and simmer gently until thick. Divide between six bowls and serve hot.</p></body></html>"
        let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in fetches += 1; return page }, modelAvailable: { false })
        let card = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/mogodu"))
        XCTAssertEqual(card.source, .imported)
        XCTAssertNotNil(card.sourceDraft)
        XCTAssertNil(card.timeMinutes)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(fallback.parses, 0)
    }

}


final class MultiPartPastedRecipeContracts: XCTestCase {
    // The owner's byte-exact paste (NBSP padding, vulgar fractions, bare sub-headings,
    // bare "Method" marker): a multi-part recipe must import WHOLE or not at all.
    private let paste = "Nespresso Hazelnut Coffee And Chocolate Trifle Recipe\nAverage Calories Per Serving: 1100 Kcal \n\nServes:\n10\n\nCooking Time:\n40-60 Minutes\nAbout This Recipe\nChocolate lovers, this one\u{2019}s for you. This Hazelnut Coffee & Chocolate Trifle layers soft homemade chocolate cake with rich chocolate custard and hazelnut coffee cream made with LANCEWOOD\u{AE} Mascarpone. Finished with toasted hazelnuts, it\u{2019}s a chocolate trifle recipe made for sharing.\u{A0}\n\nIngredients:\nChocolate Cake\u{A0}\n125g butter (\u{BD} cup)\u{A0}\n180g white sugar\u{A0}\n2 large eggs\u{A0}\n5ml vanilla extract (1 tsp)\u{A0}\n180g flour\u{A0}\nA pinch of salt\u{A0}\n10ml baking powder (2 tsp)\u{A0}\n30g cocoa powder\u{A0}\n225ml milk\u{A0}\n\u{A0}\nChocolate Custard\u{A0}\n1.5 litres full cream milk\u{A0}\n100g cornflour\u{A0}\n55g cocoa powder\u{A0}\n\u{BC} tsp salt\u{A0}\n180g castor sugar\u{A0}\n150g dark chocolate\u{A0}\n2 tsp vanilla extract\u{A0}\n\u{A0}\nHazelnut Coffee Cream\u{A0}\n500g Lancewood mascarpone\u{A0}\n750ml cream\u{A0}\n80g icing sugar\u{A0}\n100ml Nespresso Hazelnut Brownie coffee\u{A0}\n\u{A0}\nCoffee Syrup\u{A0}\n200ml Nespresso Hazelnut Brownie coffee\u{A0}\n40g castor sugar\u{A0}\n\u{A0}\nTo Garnish\u{A0}\n30g chopped toasted hazelnuts\u{A0}\nGrated chocolate\u{A0}\n\nMethod\nChocolate Cake\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}1\u{A0}\u{A0}\u{A0}\u{A0}Preheat the oven to 190\u{B0}C. Grease and line two 20cm diameter cake tins.\n\u{A0}\u{A0}\u{A0}\u{A0}2\u{A0}\u{A0}\u{A0}\u{A0}Cream the butter and sugar together using an electric or stand mixer for about 5 minutes, until very light and fluffy.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}3\u{A0}\u{A0}\u{A0}\u{A0}Add the eggs, one at a time, beating well after each addition. Add the vanilla extract. Scrape down the sides of the bowl and mix well.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}4\u{A0}\u{A0}\u{A0}\u{A0}Sift all the dry ingredients together in a separate bowl.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}5\u{A0}\u{A0}\u{A0}\u{A0}Add the dry ingredients to the creamed mixture alternately with the milk, beating well between each addition.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}6\u{A0}\u{A0}\u{A0}\u{A0}Divide the mixture between the prepared cake tins, smoothing the mixture evenly with a spatula.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}7\u{A0}\u{A0}\u{A0}\u{A0}Bake for 25\u{2013}30 minutes, or until a skewer inserted into the centre comes out clean.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}8\u{A0}\u{A0}\u{A0}\u{A0}Cool in the tins for 5\u{2013}10 minutes, then turn out and allow to cool completely on cooling racks.\u{A0}\n\u{A0}\nChocolate Custard\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}1\u{A0}\u{A0}\u{A0}\u{A0}Combine the cornflour, cocoa powder, castor sugar and salt in a bowl. Add 300ml of the milk and mix well to form a smooth paste.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}2\u{A0}\u{A0}\u{A0}\u{A0}Heat the remaining milk in a saucepan until it just starts to boil.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}3\u{A0}\u{A0}\u{A0}\u{A0}Gradually add the cornflour mixture to the hot milk, whisking constantly.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}4\u{A0}\u{A0}\u{A0}\u{A0}Continue cooking over medium heat, stirring continuously, until the mixture thickens and starts to bubble.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}5\u{A0}\u{A0}\u{A0}\u{A0}Remove from the heat. Add the vanilla extract and dark chocolate, stirring until the chocolate has completely melted and the mixture is smooth and combined.\n\u{A0}\u{A0}\u{A0}\u{A0}6\u{A0}\u{A0}\u{A0}\u{A0}Transfer to a bowl and cover with cling film, pressing it directly onto the surface of the custard to prevent a skin from forming.\n\u{A0}\u{A0}\u{A0}\u{A0}7\u{A0}\u{A0}\u{A0}\u{A0}Allow to cool to room temperature, then refrigerate until needed.\n\u{A0} \u{A0}\nHazelnut Coffee Cream\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}1\u{A0}\u{A0}\u{A0}\u{A0}Add the Lancewood mascarpone, cooled Nespresso coffee and icing sugar to a bowl. Whisk until smooth, taking care not to overmix.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}2\u{A0}\u{A0}\u{A0}\u{A0}In a separate bowl, whisk the cream to medium peaks.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}3\u{A0}\u{A0}\u{A0}\u{A0}Gently fold the whipped cream into the coffee mascarpone mixture until combined.\u{A0}\n\u{A0}\nCoffee Syrup\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}1\u{A0}\u{A0}\u{A0}\u{A0}Combine the Nespresso coffee and castor sugar, stirring until the sugar has dissolved.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}2\u{A0}\u{A0}\u{A0}\u{A0}Set aside to cool.\u{A0}\n\u{A0}\nAssembly\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}1\u{A0}\u{A0}\u{A0}\u{A0}Place one of the chocolate cakes at the bottom of a trifle dish.\n\u{A0}\u{A0}\u{A0}\u{A0}2\u{A0}\u{A0}\u{A0}\u{A0}Brush generously with the coffee syrup.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}3\u{A0}\u{A0}\u{A0}\u{A0}Spoon over approximately half of the chocolate custard, followed by half of the hazelnut coffee cream.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}4\u{A0}\u{A0}\u{A0}\u{A0}Repeat the layers with the remaining cake, coffee syrup, chocolate custardand hazelnut coffee cream.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}5\u{A0}\u{A0}\u{A0}\u{A0}Refrigerate for 1\u{2013}2 hours, or until ready to serve.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}6\u{A0}\u{A0}\u{A0}\u{A0}Finish by piping some of the hazelnut coffee cream over the top.\u{A0}\n\u{A0}\u{A0}\u{A0}\u{A0}7\u{A0}\u{A0}\u{A0}\u{A0}Sprinkle with chopped toasted hazelnuts and grated chocolate.\n"

    func testFullPasteVerifiesAsOneWholeRecipe() throws {
        let contract = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(paste))
        XCTAssertEqual(contract.ingredients.count, 28)
        // Component headings are KEPT as unmeasured review rows (the user can
        // delete a row; a lost ingredient is never recoverable). Product call
        // under the owner's product-decision grant; only To Garnish drops, on
        // the To lead-in marker.
        for component in ["Chocolate Cake", "Chocolate Custard", "Hazelnut Coffee Cream", "Coffee Syrup"] {
            XCTAssertTrue(contract.ingredients.contains { $0.quantity == 0 && $0.name == component }, component)
        }
        // Unmeasured items stay verbatim and unmeasured; no amount is invented.
        XCTAssertTrue(contract.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains("salt") })
        XCTAssertTrue(contract.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains("chocolate") })
        // Cross-component repeats with their own amounts are all kept, in order.
        XCTAssertEqual(contract.ingredients.filter { $0.name.lowercased().contains("cocoa") }.map(\.quantity), [30, 55])
        // "A pinch of salt" binds quantity-less under the ingredient's own name:
        // the pinch phrase is the source's own measure, the lead is normalised away.
        XCTAssertTrue(contract.ingredients.contains { $0.quantity == 0 && $0.name == "salt" })
        XCTAssertFalse(contract.ingredients.contains { $0.name.lowercased().hasPrefix("a pinch") })
        XCTAssertTrue(contract.method.contains("Assembly"))
        XCTAssertTrue(contract.method.contains("Refrigerate for 1\u{2013}2 hours"))
        XCTAssertTrue(contract.method.contains("190\u{00B0}C"))
        if case .verified = SourceRecipeFidelity.extraction(paste) {} else { XCTFail("full paste must verify") }
    }

    func testNBSPAndWhitespaceVariantsVerifyIdentically() throws {
        let nbsp = "\u{00A0}"
        let variant = paste.replacingOccurrences(of: " ", with: nbsp)
        let contract = try XCTUnwrap(SourceRecipeFidelity.multiPartRecipe(variant))
        XCTAssertEqual(contract.ingredients.count, 28)
    }

    func testAmbiguousMultiPartPasteFailsClosed() throws {
        // An unverifiable extra line makes every boundary ambiguous: refuse, never
        // partially certify, never reach creative generation.
        let mangled = paste.replacingOccurrences(of: "225ml milk", with: "225ml milk, salt")
        XCTAssertNil(SourceRecipeFidelity.multiPartRecipe(mangled))
        guard case .unverifiable = SourceRecipeFidelity.extraction(mangled) else { return XCTFail("ambiguous paste must fail closed") }
    }

    func testIdeaPromptIsNotARecipeImport() throws {
        guard case .none = SourceRecipeFidelity.extraction("chicken curry for 4") else { return XCTFail("an idea prompt is creative, not an import") }
    }

    func testMultiPartKeepsFoodNounItemsWithMethodPresent() throws {
        // An unmarked shaped line is an item in EVERY position, bulleted or
        // not, with a Method section present: ambiguity is never resolved by
        // dropping. "Grated Parmesan" keeps its prep-led shape through
        // unmeasuredItem, the rest bind as unmeasured items (quantity 0).
        let foods = ["Soy Sauce", "Worcestershire Sauce", "Golden Syrup", "Pasta of Choice", "Grated Parmesan"]
        for food in foods {
            let key = food.lowercased().contains("parmesan") ? "parmesan" : food.lowercased()
            for position in 0...2 {
                for bullet in ["", "* "] {
                    var items = ["200g chicken", "100g rice"]
                    items.insert(bullet + food, at: position)
                    let text = "Chicken Rice Bowl\n\nIngredients\n" + items.joined(separator: "\n") + "\n\nMethod\n1. Mix and simmer for 20 minutes."
                    guard case .verified(let c) = SourceRecipeFidelity.extraction(text) else {
                        return XCTFail("\(food) at position \(position) bullet=\(bullet.isEmpty ? "no" : "yes") must bind")
                    }
                    XCTAssertEqual(c.ingredients.count, 3, "\(food) at position \(position)")
                    XCTAssertTrue(c.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains(key) },
                                  "\(food) at position \(position) bullet=\(bullet.isEmpty ? "no" : "yes")")
                }
            }
        }
        // A standalone item line inside the Method section never changes the
        // ingredient list: positional evidence only, never a global method set.
        let inMethod = "Chicken Rice Bowl\n\nIngredients\n200g chicken\n100g rice\nSoy Sauce\n\nMethod\nSoy Sauce\n1. Mix and simmer for 20 minutes."
        guard case .verified(let m) = SourceRecipeFidelity.extraction(inMethod) else { return XCTFail("Soy Sauce with a method namesake must bind") }
        XCTAssertEqual(m.ingredients.map { $0.name }, ["chicken", "rice", "Soy Sauce"])
        // Ambiguity keeps the line: "Chicken" precedes a measured line but its
        // name is also a measured item, so it binds as an unmeasured item.
        let block = "Saucy Chicken\n\nIngredients\nChicken\n200g chicken\n100g rice\n\nMethod\nChicken\n1. Mix and simmer for 20 minutes."
        guard case .verified(let b) = SourceRecipeFidelity.extraction(block) else { return XCTFail("ambiguous shaped line binds as an item") }
        XCTAssertEqual(b.ingredients.map { $0.name }, ["Chicken", "chicken", "rice"])
        XCTAssertEqual(b.ingredients.map { $0.quantity }, [0, 200, 100])
        // A LONE shaped opener in a flat list is an item, never a heading.
        let lone = "Saucy Chicken\n\nIngredients\nCake\n200g chicken\n100g rice\n\nMethod\n1. Mix and simmer for 20 minutes."
        guard case .verified(let l) = SourceRecipeFidelity.extraction(lone) else { return XCTFail("lone shaped line binds as an item") }
        XCTAssertEqual(l.ingredients.map { $0.name }, ["Cake", "chicken", "rice"])
        XCTAssertEqual(l.ingredients.first?.quantity, 0)
        // Grouped lists keep every sauce: blank lines are not proof of
        // headings.
        let grouped = "Chicken Rice Bowl\n\nIngredients\nSoy Sauce\n200g chicken\n\nWorcestershire Sauce\n100g rice\n\nMethod\n1. Mix and simmer for 20 minutes."
        guard case .verified(let g) = SourceRecipeFidelity.extraction(grouped) else { return XCTFail("grouped list must bind") }
        XCTAssertEqual(g.ingredients.map { $0.name }, ["Soy Sauce", "chicken", "Worcestershire Sauce", "rice"])
        // An explicit For/To opener drops on the marker and never counts
        // toward anything: the ambiguous Soy Sauce beneath it still keeps.
        let forSauce = "Saucy Chicken\n\nIngredients\nFor the Sauce\nSoy Sauce\n200g chicken\n100g rice\n\nMethod\n1. Mix and simmer for 20 minutes."
        guard case .verified(let f) = SourceRecipeFidelity.extraction(forSauce) else { return XCTFail("For-the-Sauce list must bind") }
        XCTAssertEqual(f.ingredients.map { $0.name }, ["Soy Sauce", "chicken", "rice"])
        // A colon / For-To lead-in still drops.
        let colon = "Saucy Chicken\n\nIngredients\nFor the Sauce:\n200g chicken\n100g rice\n\nMethod\n1. Mix and simmer for 20 minutes."
        guard case .verified(let k) = SourceRecipeFidelity.extraction(colon) else { return XCTFail("colon heading binds") }
        XCTAssertEqual(k.ingredients.map { $0.name }, ["chicken", "rice"])
    }

}

final class CaptionDishAndQuantityLessContracts: XCTestCase {
    // The reel caption the owner tested: names its dish in the first line, lists
    // ingredients without quantities, and points at the bio for the full recipe.
    private let reel = "Marry Me Shrimp Pasta - creamy garlic shrimp in a rich sun-dried tomato Parmesan sauce. Alwaays a hit and ready in 30 minutes \u{2728}\n\nIngredients\nFor the Shrimp\n* Shrimp, peeled & deveined\n* Oregano\n* Paprika\n* Garlic powder\n* Salt & black pepper\n* Chili flakes\n\nFor the Sauce\n* Garlic\n* Shallot\n* Dry white wine\n* Pasta water\n* Heavy cream\n* Tomato paste\n* Paprika\n* Oregano\n* Parmesan cheese\n* Sun-dried tomatoes\n* Fresh thyme\n* Chili flakes\n* Pasta of choice\nFull recipe linked in my bio \u{1F517}\n\nJune 11"

    func testCaptionHeadingsAreStructuralAndTitleCaseItemsAreRetained() throws {
        // A heading needs a STRUCTURAL marker: a trailing colon or a "For ..." /
        // "To ..." lead-in. Capitalisation and closing food nouns are normal copy,
        // they never drop an ingredient.
        guard case .verified(let reelContract) = SourceRecipeFidelity.extraction(reel) else { return XCTFail() }
        XCTAssertEqual(reelContract.ingredients.count, 19)
        // Title Case "Pasta of Choice" is RETAINED: 19 stay 19, and an ambiguous
        // line always stays an ingredient for the fidelity check to judge.
        let titleCase = reel.replacingOccurrences(of: "Pasta of choice", with: "Pasta of Choice")
        guard case .verified(let c) = SourceRecipeFidelity.extraction(titleCase) else { return XCTFail() }
        XCTAssertEqual(c.ingredients.count, 19)
        XCTAssertTrue(c.ingredients.contains { $0.name.lowercased().contains("pasta of") })
        // A closing food noun ("Pasta Sauce") is an ITEM, never a heading: 20 bind.
        let nounLine = reel.replacingOccurrences(of: "For the Sauce", with: "Pasta Sauce")
        guard case .verified(let h) = SourceRecipeFidelity.extraction(nounLine) else { return XCTFail() }
        XCTAssertEqual(h.ingredients.count, 20)
        XCTAssertTrue(h.ingredients.contains { $0.name == "Pasta Sauce" })
        // A colon-led or lead-in line still reads as a heading, exactly like the
        // reel's own "For the Shrimp" / "For the Sauce".
        let colonHeaded = reel.replacingOccurrences(of: "For the Sauce", with: "To Assemble:")
        guard case .verified(let k) = SourceRecipeFidelity.extraction(colonHeaded) else { return XCTFail() }
        XCTAssertEqual(k.ingredients.count, 19)
        XCTAssertFalse(k.ingredients.contains { $0.name.hasSuffix(":") || $0.name.lowercased().hasPrefix("for the") })
    }

    func testClosingFoodNounNeverMakesAHeading() throws {
        // Title Case lines ending in a section noun are food, not headings.
        let caption = "Weeknight tray bake\n\nIngredients\n* Worcestershire Sauce\n* Soy Sauce\n* Vanilla Custard\n* Golden Syrup\n* Chicken\n* Rice"
        guard case .verified(let c) = SourceRecipeFidelity.extraction(caption) else { return XCTFail("food-noun items must bind") }
        XCTAssertEqual(c.ingredients.map { $0.name },
                       ["Worcestershire Sauce", "Soy Sauce", "Vanilla Custard", "Golden Syrup", "Chicken", "Rice"])
    }

    func testCaptionFirstLineNamesBindTheTitle() throws {
        guard case .verified(let c) = SourceRecipeFidelity.extraction(reel) else { return XCTFail("reel caption must verify") }
        XCTAssertEqual(c.dishes, ["Marry Me Shrimp Pasta"])
    }

    func testCaptionDishNameSplitsOnEnDashEmDashHyphenAndColon() {
        // The dash set lives in an ordinary Swift string (\u{2013} there; the
        // \x{...} ICU escapes are only valid inside the raw regex strings).
        XCTAssertEqual(SourceRecipeFidelity.captionDishName("Mogodu \u{2013} slow braised, Sunday pot"), "Mogodu")
        XCTAssertEqual(SourceRecipeFidelity.captionDishName("Mogodu \u{2014} slow braised, Sunday pot"), "Mogodu")
        XCTAssertEqual(SourceRecipeFidelity.captionDishName("Mogodu - slow braised, Sunday pot"), "Mogodu")
        XCTAssertEqual(SourceRecipeFidelity.captionDishName("Mogodu: slow braised, Sunday pot"), "Mogodu")
    }

    func testQuantityLessListStaysQuantityLess() throws {
        guard case .verified(let c) = SourceRecipeFidelity.extraction(reel) else { return XCTFail() }
        XCTAssertEqual(c.ingredients.count, 19)
        XCTAssertTrue(c.ingredients.allSatisfy { $0.quantity == 0 })
        XCTAssertEqual(c.ingredients.first?.name, "Shrimp")
        XCTAssertTrue(c.method.isEmpty)
        // An invented amount on a bound run is caught: qty-0 items bind by name alone.
        var card = RecipeCard(title: "Marry Me Shrimp Pasta", ingredients: c.ingredients, steps: [], source: .appleIntelligence)
        XCTAssertTrue(c.issues(card).isEmpty)
        card.ingredients[1].quantity = 2
        XCTAssertTrue(c.issues(card).contains { $0.contains("without an amount") })
        card = RecipeCard(title: "Marry Me Shrimp Pasta", ingredients: c.ingredients, steps: [], source: .appleIntelligence)
        card.ingredients.removeFirst()
        XCTAssertTrue(c.issues(card).contains { $0.contains("exactly the source") })
    }

    func testMeasuredLineInCaptionListFailsClosed() throws {
        let measured = reel.replacingOccurrences(of: "* Oregano\n* Paprika", with: "* Oregano\n* 500 g beef\n* Paprika")
        guard case .unverifiable = SourceRecipeFidelity.extraction(measured) else { return XCTFail("a measured line in a quantity-less list must fail closed") }
    }

    func testCaptionWithoutDishKeepsUnknownDishPath() throws {
        // No first-line title break, no glossary dish: the caption names nothing, so
        // its list still binds and the title stays the honest Unknown-dish question.
        let anon = reel.replacingOccurrences(of: "Marry Me Shrimp Pasta - ", with: "")
        XCTAssertNil(SourceRecipeFidelity.captionDishName(anon))
        guard case .verified(let c) = SourceRecipeFidelity.extraction(anon) else { return XCTFail("anonymous caption list still binds") }
        XCTAssertTrue(c.dishes.isEmpty)
        XCTAssertEqual(c.ingredients.count, 19)
    }
}

final class RequestScopedContractContracts: XCTestCase {
    private final class Echo: BackendService {
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            RecipeCard(title: request.text ?? "", source: .mock)
        }
        func publish(_ card: RecipeCard) async throws -> String { "unused" }
        func fetchShared(slug: String) async throws -> RecipeCard? { nil }
    }

    // The contract travels WITH its own parse result; no shared static exists to
    // cross. Two interleaved parses keep their own inputs and their own (here
    // unbound, nil) contracts. Bound-contract content itself is pinned by the
    // extraction fixtures above; model generation stays UNRUN on this host.
    func testInterleavedParsesKeepTheirOwnInputsAndContracts() async throws {
        let backend = OnDeviceBackend(fallback: Echo(), modelAvailable: { false })
        async let a = backend.parseRecipeWithContract(.init(mode: .prompt, text: "chicken curry for 4"))
        async let b = backend.parseRecipeWithContract(.init(mode: .prompt, text: "vegan pancakes for 2"))
        let (ra, rb) = try await (a, b)
        XCTAssertEqual(ra.card.title, "chicken curry for 4")
        XCTAssertEqual(rb.card.title, "vegan pancakes for 2")
        XCTAssertNil(ra.contract)
        XCTAssertNil(rb.contract)
    }
}

final class DishConfirmationContracts: XCTestCase {
    private func contract(dishes: [String]) -> SourceRecipeFidelity.Contract {
        SourceRecipeFidelity.Contract(text: "source", ingredients: [
            Ingredient(name: "beef tripe", quantity: 1.5, unit: "kg"),
            Ingredient(name: "onions", quantity: 2, unit: "pcs")], method: "Simmer 150 minutes.", dishes: dishes)
    }

    func testConfirmSetsOnlyTheTitleAndRestoresSourceIngredients() throws {
        let c = contract(dishes: [])
        var card = RecipeCard(title: "Unknown dish", ingredients: [.init(name: "oil", quantity: 2, unit: "tbsp")],
                              steps: [], source: .appleIntelligence)
        SourceRecipeFidelity.applyingDishConfirmation(&card, contract: c, hint: "Chakalaka")
        XCTAssertEqual(card.title, "Chakalaka")
        XCTAssertEqual(card.ingredients.map(\.name), ["beef tripe", "onions"])
        XCTAssertEqual(card.ingredients.map(\.quantity), [1.5, 2])
    }

    func testConfirmMatchingTheSourceDishAppliesIt() throws {
        var card = RecipeCard(title: "Unknown dish", ingredients: [], steps: [], source: .appleIntelligence)
        let c = contract(dishes: ["Mogodu"])
        SourceRecipeFidelity.applyingDishConfirmation(&card, contract: c, hint: "mogodu")
        XCTAssertEqual(card.title, "mogodu")
        XCTAssertNil(card.aiNote)
    }

    func testContradictingConfirmKeepsTheSourceAndSaysSo() throws {
        var card = RecipeCard(title: "Unknown dish", ingredients: [], steps: [], source: .appleIntelligence)
        let c = contract(dishes: ["Mogodu"])
        SourceRecipeFidelity.applyingDishConfirmation(&card, contract: c, hint: "Chakalaka")
        XCTAssertEqual(card.title, "Mogodu")
        XCTAssertEqual(card.ingredients.map(\.name), ["beef tripe", "onions"])
        XCTAssertTrue(card.aiNote?.contains("Chakalaka") == true)
        XCTAssertTrue(card.aiNote?.contains("not applied") == true)
    }
}

final class ExampleEchoRejectionContracts: XCTestCase {
    private func exampleCard() -> RecipeCard {
        RecipeCard(title: "Unknown dish", ingredients: [
            .init(name: "beef tripe", quantity: 1.5, unit: "kg"), .init(name: "onions", quantity: 2, unit: "pcs"),
            .init(name: "garlic", quantity: 3, unit: "cloves"), .init(name: "curry powder", quantity: 2, unit: "tsp"),
            .init(name: "beef stock", quantity: 500, unit: "ml")], steps: [], source: .appleIntelligence)
    }

    func testEchoFromUnrelatedSourceIsRejected() throws {
        XCTAssertTrue(OnDeviceBackend.isExampleEcho(exampleCard(), sourceText: "Log in to see photos and videos from your friends."))
    }

    func testGenuineTripeSourceIsNotAnEcho() throws {
        XCTAssertFalse(OnDeviceBackend.isExampleEcho(exampleCard(), sourceText: "Mogodu Monday! you need: tripe, onions"))
    }
}

final class URLPageMultiPartContracts: XCTestCase {
    // The exact text the LANCEWOOD trifle page yields through htmlToText: navigation
    // repeats "Ingredients"/"Method" before the real sections, the recipe lists five
    // components with measured items, a pinch and a vulgar fraction, and an FAQ tail.
    private let page = "Ingredients\nMethod\nNovember 18, 2026\nNespresso Hazelnut Coffee and Chocolate Trifle Recipe\nAverage Calories Per Serving: 1100 kcal\nShare\nDownload\nServes:\n10\nCooking Time:\n40-60 Minutes\nRelated Tags\nNo data was found\nAbout This Recipe\nChocolate lovers, this one&#8217;s for you. This Hazelnut Coffee & Chocolate Trifle layers soft homemade chocolate cake with rich chocolate custard and hazelnut coffee cream made with LANCEWOOD® Mascarpone. Finished with toasted hazelnuts, it&#8217;s a chocolate trifle recipe made for sharing.\nExpand Full Description\nThere&#8217;s plenty to savour in every spoonful: soft chocolate cake carrying a hint of coffee syrup, smooth custard made with dark chocolate, and airy mascarpone cream infused with Nespresso Hazelnut Brownie coffee.\nLANCEWOOD® Mascarpone gives the cream its richness, while separately whipped cream makes the filling beautifully light. A scattering of chopped toasted hazelnuts adds crunch, with grated chocolate to finish.\nThe chocolate cake is baked from scratch, then layered with the custard and coffee cream in a trifle dish. Chill the assembled dessert for 1–2 hours, allowing the layers to settle before serving.\nIngredients:\nChocolate Cake\n125g butter (½ cup)\n180g white sugar\n2 large eggs\n5ml vanilla extract (1 tsp)\n180g flour\nA pinch of salt\n10ml baking powder (2 tsp)\n30g cocoa powder\n225ml milk\nChocolate Custard\n1.5 litres full cream milk\n100g cornflour\n55g cocoa powder\n¼ tsp salt\n180g castor sugar\n150g dark chocolate\n2 tsp vanilla extract\nHazelnut Coffee Cream\n500g Lancewood mascarpone\n750ml cream\n80g icing sugar\n100ml Nespresso Hazelnut Brownie coffee\nCoffee Syrup\n200ml Nespresso Hazelnut Brownie coffee\n40g castor sugar\nTo Garnish\n30g chopped toasted hazelnuts\nGrated chocolate\nConvert Your Measurements\nView Full Conversion Table\nMethod\nChocolate Cake\nPreheat the oven to 190°C. Grease and line two 20cm diameter cake tins.\nCream the butter and sugar together using an electric or stand mixer for about 5 minutes, until very light and fluffy.\nAdd the eggs, one at a time, beating well after each addition. Add the vanilla extract. Scrape down the sides of the bowl and mix well.\nSift all the dry ingredients together in a separate bowl.\nAdd the dry ingredients to the creamed mixture alternately with the milk, beating well between each addition.\nDivide the mixture between the prepared cake tins, smoothing the mixture evenly with a spatula.\nBake for 25–30 minutes, or until a skewer inserted into the centre comes out clean.\nCool in the tins for 5–10 minutes, then turn out and allow to cool completely on cooling racks.\nChocolate Custard\nCombine the cornflour, cocoa powder, castor sugar and salt in a bowl. Add 300ml of the milk and mix well to form a smooth paste.\nHeat the remaining milk in a saucepan until it just starts to boil.\nGradually add the cornflour mixture to the hot milk, whisking constantly.\nContinue cooking over medium heat, stirring continuously, until the mixture thickens and starts to bubble.\nRemove from the heat. Add the vanilla extract and dark chocolate, stirring until the chocolate has completely melted and the mixture is smooth and combined.\nTransfer to a bowl and cover with cling film, pressing it directly onto the surface of the custard to prevent a skin from forming.\nAllow to cool to room temperature, then refrigerate until needed.\nHazelnut Coffee Cream\nAdd the Lancewood mascarpone, cooled Nespresso coffee and icing sugar to a bowl. Whisk until smooth, taking care not to overmix.\nIn a separate bowl, whisk the cream to medium peaks.\nGently fold the whipped cream into the coffee mascarpone mixture until combined.\nCoffee Syrup\nCombine the Nespresso coffee and castor sugar, stirring until the sugar has dissolved.\nSet aside to cool.\nAssembly\nPlace one of the chocolate cakes at the bottom of a trifle dish.\nBrush generously with the coffee syrup.\nSpoon over approximately half of the chocolate custard, followed by half of the hazelnut coffee cream.\nRepeat the layers with the remaining cake, coffee syrup, chocolate custard and hazelnut coffee cream.\nRefrigerate for 1–2 hours, or until ready to serve.\nFinish by piping some of the hazelnut coffee cream over the top.\nSprinkle with chopped toasted hazelnuts and grated chocolate.\nFAQ's\n1. How do you make a chocolate trifle?\nTo make this chocolate trifle, bake two chocolate cakes and prepare a dark chocolate custard. Whisk LANCEWOOD® Mascarpone with cooled hazelnut coffee and icing sugar, then fold in whipped cream. Layer the cakes with coffee syrup, custard and cream, and chill before garnishing.\n2. What are the layers in this chocolate trifle?\nThis trifle is built in two sets of layers: chocolate cake brushed with coffee syrup, chocolate custard and hazelnut coffee mascarpone cream. The pattern is repeated in a trifle dish, then finished with toasted hazelnuts and grated chocolate before serving.\n3. How long should a trifle chill before serving?\n"

    func testPageVerifiesWithAllComponents() throws {
        guard case .verified(let c) = SourceRecipeFidelity.extraction(page) else { return XCTFail("page must verify") }
        XCTAssertEqual(c.ingredients.count, 28)
        XCTAssertTrue(c.method.contains("190"))
        XCTAssertFalse(c.method.contains("FAQ"))
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains("salt") })
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 0.25 })
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains("chocolate") })
    }

    func testPageClippedBeforeTheRecipeNeverCertifies() throws {
        let clipped = String(page.prefix(3500))
        if case .verified = SourceRecipeFidelity.extraction(clipped) { XCTFail("a clipped page must never certify") }
    }
}

final class RecipeShapedFailClosedContracts: XCTestCase {
    func testShortMarkerFreeMeasuredRecipeFailsClosed() throws {
        let text = "200g flour\n100g sugar\n1. Mix well\n2. Bake until done"
        guard case .unverifiable = SourceRecipeFidelity.extraction(text) else { return XCTFail("recipe-shaped text must fail closed, not generate") }
    }

    func testKnownDishWordDoesNotRescueRecipeShapedText() throws {
        let text = "mogodu\n200g flour\n100g sugar\n1. Mix well\n2. Bake until done"
        guard case .unverifiable = SourceRecipeFidelity.extraction(text) else { return XCTFail("a glossary hit must not rescue recipe-shaped text") }
    }

    func testIdeaPromptKeepsCreativePath() throws {
        guard case .none = SourceRecipeFidelity.extraction("something comforting with chicken for a cold night") else { return XCTFail("an idea prompt is not recipe-shaped") }
    }

    func testASCIIFractionsAndMixedNumbersRoundTrip() throws {
        let text = "Ingredients:\n1/4 tsp salt\n1 1/2 cups flour\n1/3 cup milk\n200g sugar\n\nMethod\n1. Mix everything together for 2 minutes.\n2. Bake for 30 minutes."
        guard case .verified(let c) = SourceRecipeFidelity.extraction(text) else { return XCTFail("ASCII fractions must verify") }
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 0.25 })
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 1.5 })
        // 1/3 = 0.333... locally, 0.33 in the parser: they compare at the parser's
        // own hundredth precision, never binary equality.
        XCTAssertTrue(c.ingredients.contains { $0.name == "milk" && ($0.quantity * 100).rounded() == 33 })
    }
}

final class PagePromptAndRegexContracts: XCTestCase {
    /// The Lancewood finding: the recipe starts past the old 3500-char prompt cap.
    /// The backend feeds the verified contract's own text and RecipePrompt.page
    /// never clips, so the FINAL assembled prompt carries the ingredient lines.
    func testFinalPagePromptCarriesIngredientLinesPastTheOldCap() throws {
        let recipe = "Ingredients:\n125g butter\n180g white sugar\n2 large eggs\n\nMethod\n1. Cream the butter and sugar for 5 minutes.\n2. Add the eggs and bake for 30 minutes.\n"
        let page = String(repeating: "Navigation boilerplate. ", count: 200) + "\n" + recipe
        XCTAssertGreaterThan(page.range(of: "125g butter")!.lowerBound.utf16Offset(in: page), 3500)
        let contract = try XCTUnwrap(SourceRecipeFidelity.structuredRecipe(page) ?? SourceRecipeFidelity.multiPartRecipe(page))
        let prompt = RecipePrompt.page(String(contract.text.prefix(6000)))
        for line in ["125g butter", "180g white sugar", "2 large eggs"] {
            XCTAssertTrue(prompt.contains(line), "the final prompt must carry \(line)")
        }
    }

    /// Every NSRegularExpression pattern must compile under ICU: the \u{XXXX} brace
    /// syntax is a Swift escape, not ICU (status 66307 on ICU70), and a bad pattern
    /// throws at first use instead of matching. Each assertion below exercises a
    /// pattern path, so it proves the pattern compiled AND matched, not its tokens.
    func testRegexPathsCompileAndMatch() throws {
        // Vulgar-fraction classes (measuredItem, caption guard, measure equivalents).
        let vulgar = "Ingredients:\n\u{00BC} tsp salt\n200g sugar\n2 eggs\n\nMethod\n1. Mix for 2 minutes.\n2. Bake for 30 minutes."
        guard case .verified(let c) = SourceRecipeFidelity.extraction(vulgar) else { return XCTFail("vulgar fraction pattern must compile and match") }
        XCTAssertTrue(c.ingredients.contains { $0.quantity == 0.25 })
        // Bullet/dash lead class (isRecipeShaped): bulleted measured lines plus steps
        // are recipe-shaped, so they bind or fail closed, never fall to creative.
        let bulleted = "\u{2022} 200g sugar\n\u{2022} 2 eggs\n1. Mix for 2 minutes.\n2. Bake for 30 minutes."
        if case .none = SourceRecipeFidelity.extraction(bulleted) { XCTFail("bullet lead pattern must compile and match") }
        // NBSP collapse (multiPart): covered byte-exactly by the trifle paste NBSP
        // variant above; an invalid collapse pattern fails that parse outright.
    }
}
