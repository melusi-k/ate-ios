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

    func testPastedStructuredRecipeDoesNotSubstituteDemoWhenModelIsUnavailable() async {
        let fallback = Fallback()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        do {
            _ = try await backend.parseRecipe(.init(mode: .prompt, text: pastedTripeRecipe))
            XCTFail("a pasted structured recipe must not become a demo")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No demo recipe was substituted")) }
        XCTAssertEqual(fallback.parses, 0)
    }

    func testUnverifiableStructureFailsClosedBeforeCreativeGenerationOrDemo() async {
        let page = "<html><body><h1>Mogodu</h1><p>Serves 6</p><h2>Ingredients</h2><p>1 kg beef tripe 2 onions salt to taste</p><h2>Method</h2><p>Simmer 150 minutes, fry 5 minutes, season.</p></body></html>"
        for available in [false, true] {
            let fallback = Fallback()
            var fetches = 0
            let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in
                fetches += 1; return page
            }, modelAvailable: { available })
            do {
                _ = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/mogodu"))
                XCTFail("recognizable-but-unverifiable structure must fail closed")
            } catch {
                let message = error.localizedDescription
                XCTAssertTrue(message.contains("couldn't verify") || message.contains("could not be verified"), message)
            }
            XCTAssertEqual(fetches, 1)
            XCTAssertEqual(fallback.parses, 0)
        }
    }

    func testUnverifiableCaptionFailsClosedBeforeCreativeGenerationOrDemo() async {
        let badCaption = "You need 1 kg beef tripe, 2 onions (salt). Simmer 150 minutes, season."
        for available in [false, true] {
            let fallback = Fallback()
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available })
            do {
                _ = try await backend.parseRecipe(.init(mode: .prompt, text: badCaption))
                XCTFail("recognizable-but-unverifiable caption must fail closed (model available: \(available))")
            } catch {
                let message = error.localizedDescription
                XCTAssertTrue(message.contains("couldn't verify") || message.contains("could not be verified"), message)
            }
            XCTAssertEqual(fallback.parses, 0)
        }
    }

    func testStructuredPageDoesNotSubstituteDemoWhenModelIsUnavailable() async {
        let fallback = Fallback()
        var fetches = 0
        let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in
            fetches += 1
            return "<html><head><title>Mogodu</title></head><body><h1>Mogodu</h1><p>Serves 6</p><h2>Ingredients</h2><p>1.2 kg beef tripe, cleaned and cut into strips<br>2 onions, chopped<br>3 cloves garlic, crushed<br>2 tsp curry powder<br>500 ml beef stock<br>1.5 l water<br>1 tsp salt<br>2 tbsp oil</p><h2>Method</h2><p>Cut the cleaned tripe into strips. Cover with the water and salt. Simmer covered until tender, about 150 minutes, then drain. Fry the onion and garlic in the oil until golden, 8 minutes. Stir in the curry powder, add the drained tripe and stock and simmer gently until thick. Divide between six bowls and serve hot.</p></body></html>"
        }, modelAvailable: { false })
        do {
            _ = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/mogodu"))
            XCTFail("A structured source must not become a demo recipe")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No demo recipe was substituted")) }
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(fallback.parses, 0)
    }
}
