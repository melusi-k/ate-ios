import XCTest
@testable import Ate

/// C-AI-01..03, C-FIX-04/05/07, P0 duplicate saves (build 81 feedback).
final class QualityAndDedupeTests: XCTestCase {
    private func ribs(conf: Double = 0.9) -> RecipeCard {
        var c = RecipeCard(title: "Ribs and lemon pepper wings", servings: 4,
                           ingredients: [.init(name: "pork ribs", quantity: 1, unit: "kg"), .init(name: "chicken wings", quantity: 800, unit: "g"),
                                         .init(name: "lemon pepper", quantity: 2, unit: "tbsp")],
                           steps: [.init(order: 1, instruction: "Cook ribs", timeSeconds: nil),
                                   .init(order: 2, instruction: "Bake the wings until golden", timeSeconds: 1800)],
                           source: .appleIntelligence)
        c.aiConfidence = conf; c.aiAlternatives = ["Sticky ribs", "Lemon pepper wings"]
        return c
    }

    // C-AI-01: 80% threshold
    func testThresholdAsksBelow80AndSkipsAbove() {
        XCTAssertTrue(RecipeQuality.shouldAskDish(ribs(conf: 0.79), alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.shouldAskDish(ribs(conf: 0.8), alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.shouldAskDish(ribs(conf: 0.5), alreadyConfirmed: true), "asked once; then draft state")
        XCTAssertEqual(RecipeQuality.guesses(ribs(conf: 0.5)).first, "Ribs and lemon pepper wings", "pre-filled with inferred name")
        XCTAssertEqual(RecipeQuality.guesses(ribs(conf: 0.5)).count, 3)
        var manual = ribs(conf: 0.1); manual.source = .manual
        XCTAssertFalse(RecipeQuality.shouldAskDish(manual, alreadyConfirmed: false))
        XCTAssertFalse(RecipeQuality.needsInput(manual))
    }
    // C-AI-02: output quality
    func testQualityIssuesForThinCard() {
        let i = RecipeQuality.issues(ribs())
        XCTAssertTrue(i.contains { $0.contains("4 ingredients") })
        XCTAssertTrue(i.contains { $0.contains("temperature") })
        XCTAssertTrue(i.contains { $0.contains("too vague") })
        XCTAssertTrue(RecipeQuality.needsInput(ribs()), "thin card is a draft even at 90%")
        var good = ribs()
        good.ingredients.append(.init(name: "garlic", quantity: 3, unit: "cloves"))
        good.steps = [.init(order: 1, instruction: "Rub the ribs with garlic and lemon pepper, cover and bake at 160°C for 2 hours", timeSeconds: nil),
                      .init(order: 2, instruction: "Roast the wings at 220 °C until golden and crisp, 30 minutes", timeSeconds: nil)]
        XCTAssertEqual(RecipeQuality.issues(good), [])
        XCTAssertFalse(RecipeQuality.needsInput(good))
    }
    // Cover tile icons by dish type
    func testTileIconsByDishType() {
        XCTAssertEqual(CoverLogic.tile(title: "Sticky ribs", cuisine: nil, ingredients: ["1 teaspoon paprika"]).symbol, "flame", "ribs is not a teacup")
        XCTAssertEqual(CoverLogic.tile(title: "Chicken sandwich", cuisine: nil, ingredients: []).symbol, "takeoutbag.and.cup.and.straw")
        XCTAssertEqual(CoverLogic.tile(title: "Rooibos iced tea", cuisine: nil, ingredients: []).symbol, "cup.and.saucer")
        XCTAssertNotEqual(CoverLogic.tile(title: "Steak", cuisine: nil, ingredients: []).symbol, "cup.and.saucer")
    }
    // P0 duplicate saves
    func testDedupeMergesExactDuplicatesWithinMinutes() {
        let t = 1_760_000_000_000.0
        var a = ribs(); a.id = "a"; a.createdAt = t
        var b = ribs(); b.id = "b"; b.createdAt = t + 60_000; b.favorite = true
        var c = ribs(); c.id = "c"; c.createdAt = t + 120_000
        var d = ribs(); d.id = "a"; d.createdAt = t            // same id twice
        var later = ribs(); later.id = "z"; later.createdAt = t + 3 * 86_400_000   // a deliberate re-save days later is kept
        var other = ribs(); other.id = "o"; other.title = "Other"
        let r = RecipeLogic.dedupe([a, b, c, d, later, other])
        XCTAssertEqual(r.cards.map(\.id), ["a", "z", "o"])
        XCTAssertEqual(Set(r.removedIDs), ["b", "c"])
        XCTAssertTrue(r.cards[0].favorite, "merged copy keeps the favourite flag")
    }
    @MainActor func testAddIsIdempotentForTheSameDraftID() {
        let s = AppStore(context: nil, backend: MockBackend())
        let before = s.recipes.count
        var r = ribs(); r.id = "draft-1"
        s.add(r); s.add(r); s.add(r)
        XCTAssertEqual(s.recipes.count, before + 1)
    }
    // C-FIX-05
    func testSpotlightSuggestionsCappedAtThreeFavourites() {
        var cards = (0..<10).map { RecipeCard(id: "r\($0)", title: "Recipe \($0)") }
        cards[4].favorite = true; cards[7].favorite = true
        let s = RecipeEntityQuery.suggestions(cards)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(Set(s.prefix(2).map(\.id)), ["r4", "r7"])
    }
    // C-FIX-07
    func testShoppingListReturnsTextValues() {
        let items = [ShoppingItem(name: "milk", quantity: 2, unit: "l"), ShoppingItem(name: "eggs", quantity: 0, unit: "")]
        XCTAssertEqual(SiriAnswers.listValues(items), ["milk (2 l)", "eggs"])
    }
}

/// Issue #144: deterministic checks for malformed generated recipe output.
final class PhotoRecipeOutputValidationTests: XCTestCase {
    private func generatedCard() -> RecipeCard {
        var card = RecipeCard(
            title: "Tomato and egg stew",
            servings: 2,
            ingredients: [
                .init(name: "tomatoes", quantity: 4, unit: "pcs"),
                .init(name: "eggs", quantity: 2, unit: "pcs"),
                .init(name: "oil", quantity: 1, unit: "tbsp")
            ],
            steps: [
                .init(order: 1, instruction: "Heat the oil in a pan over medium heat.", timeSeconds: 120),
                .init(order: 2, instruction: "Add tomatoes and simmer until softened.", timeSeconds: 600),
                .init(order: 3, instruction: "Stir in the eggs and cook until set.", timeSeconds: 300)
            ],
            source: .photoGuess
        )
        card.aiConfidence = 0.85
        return card
    }

    func testGeneratedCardWithValidStructureHasNoStructuralIssues() {
        let issues = RecipeQuality.issues(generatedCard())
        XCTAssertFalse(issues.contains { $0.contains("positive, finite quantity") })
        XCTAssertFalse(issues.contains { $0.contains("unique order") })
        XCTAssertFalse(issues.contains { $0.contains("non-empty title") })
    }

    func testGeneratedOutputRejectsMissingTitleInvalidQuantityAndInvalidConfidence() {
        var card = generatedCard()
        card.title = "  "
        card.ingredients[0].quantity = .nan
        card.aiConfidence = 1.5

        let issues = RecipeQuality.issues(card)
        XCTAssertTrue(issues.contains { $0.contains("non-empty title") })
        XCTAssertTrue(issues.contains { $0.contains("positive, finite quantity") })
        XCTAssertTrue(issues.contains { $0.contains("between 0 and 1") })
        XCTAssertTrue(RecipeQuality.needsInput(card))
    }

    func testGeneratedOutputRejectsBlankIngredientAndDuplicateStepOrder() {
        var card = generatedCard()
        card.ingredients[0].name = "  "
        card.steps[1].order = card.steps[0].order

        let issues = RecipeQuality.issues(card)
        XCTAssertTrue(issues.contains { $0.contains("needs a name") })
        XCTAssertTrue(issues.contains { $0.contains("unique order") })
    }

    func testOutputStructureChecksDoNotChangeImportedRecipeValidation() {
        var card = generatedCard()
        card.source = .jsonLD
        card.title = "  "
        card.ingredients[0].quantity = 0
        card.aiConfidence = 1.5

        let issues = RecipeQuality.issues(card)
        XCTAssertFalse(issues.contains { $0.contains("non-empty title") })
        XCTAssertFalse(issues.contains { $0.contains("positive, finite quantity") })
        XCTAssertFalse(issues.contains { $0.contains("between 0 and 1") })
    }
}

/// Foundation Models round: errors, examples, streamed preview, rendering from structured data.
final class FoundationModelsPatternTests: XCTestCase {
    func testEveryGenerationFailureHasADistinctClearMessage() {
        let msgs = GenerationFailure.allCases.map(\.message)
        XCTAssertEqual(Set(msgs).count, msgs.count)
        XCTAssertTrue(GenerationFailure.tooLong.message.contains("too long"))
        XCTAssertTrue(GenerationFailure.guardrail.message.contains("wouldn't"))
        XCTAssertTrue(GenerationFailure.assetsUnavailable.message.contains("getting ready"))
    }
    func testInstructionsHavePersonaRulesAndExamples() {
        let i = RecipePrompt.instructions
        for must in ["South African home-cooking expert", "at least 4 real ingredients", "°C", "Chakalaka", "bake at 160°C", "First identify the dish"] {
            XCTAssertTrue(i.contains(must), must)
        }
    }
    func testExampleRecipesMeetTheQualityBar() {
        let ribs = RecipeCard(title: "Sticky pork ribs", servings: 4,
                              ingredients: [.init(name: "pork ribs", quantity: 1.2, unit: "kg"), .init(name: "brown sugar", quantity: 3, unit: "tbsp"),
                                            .init(name: "smoked paprika", quantity: 2, unit: "tsp"), .init(name: "garlic", quantity: 3, unit: "cloves")],
                              steps: [.init(order: 1, instruction: "Rub the ribs with sugar, paprika and garlic", timeSeconds: nil),
                                      .init(order: 2, instruction: "Wrap in foil and bake at 160°C until tender", timeSeconds: 7200)],
                              source: .appleIntelligence)
        XCTAssertEqual(RecipeQuality.issues(ribs), [])
    }
    func testStreamPreviewIsEquatableForLiveAnimation() {
        XCTAssertNotEqual(RecipeStreamPreview(title: nil), RecipeStreamPreview(title: "Mogodu"))
    }
}

/// Code-along 205: tool-backed glossary, conditional prompt lines, schema A/B default.
final class CodeAlong205Tests: XCTestCase {
    func testLookupRegionalDishReturnsGlossaryEntries() {
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("mogodu").contains("tripe"))
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("umngqusho").contains("samp"))
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("chakalaka").contains("Chakalaka"))
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("lasagne").hasPrefix("No glossary entry"))
    }
    func testInstructionsNoLongerDumpTheGlossary() {
        XCTAssertFalse(RecipePrompt.prompt("mogodu").contains("about 180 min total"), "entries come from the tool, not the prompt")
        XCTAssertTrue(RecipePrompt.prompt("mogodu").contains("lookupRegionalDish"))
    }
    func testConditionalContextLines() {
        let c = RecipePrompt.context(for: "Vegan chakalaka for 6", region: "ZA")
        XCTAssertEqual(c.dietary, ["vegan"]); XCTAssertEqual(c.servings, 6); XCTAssertEqual(c.region, "South Africa")
        XCTAssertEqual(RecipePrompt.contextLines(c).count, 3)
        XCTAssertEqual(RecipePrompt.contextLines(RecipePrompt.context(for: "pasta", region: "US")), [])
    }
    func testSchemaLeftOutByDefault() {
        XCTAssertFalse(RecipePrompt.includeSchemaInPrompt)
        XCTAssertTrue(RecipePrompt.exampleLead.contains("don't copy its content"))
    }
}

/// Photo regressions from device testing. Fixtures are the Vision outputs (labels + confidences) recorded for the
/// photos; the simulator has no Vision food model parity, so the pure decision logic is tested on these.
final class PhotoRegressionTests: XCTestCase {
    static let omeletteToast: [(String, Float)] = [("food", 0.93), ("omelette", 0.71), ("toast", 0.58), ("bread", 0.41), ("plate", 0.66),
                                                   ("tableware", 0.6), ("egg", 0.35), ("breakfast", 0.52), ("dishware", 0.4), ("cheese", 0.12)]
    static let twoPlatesOmelette: [(String, Float)] = [("food", 0.9), ("omelette", 0.7), ("omelettes", 0.4), ("plate", 0.7), ("tableware", 0.6), ("toast", 0.5)]
    static let cheeseSandwich: [(String, Float)] = [("food", 0.9), ("sandwich", 0.82), ("bread", 0.6), ("cheese", 0.48), ("lettuce", 0.36),
                                                    ("sausage", 0.3), ("sauce", 0.27), ("plate", 0.5)]
    /// Ground truth for the live South African feast run: beef stew, mogodu, amanqina, dombolo, chakalaka and morogo.
    static let southAfricanFeast: [(String, Float)] = [("food", 0.98), ("beef_stew", 0.91), ("tripe", 0.88),
                                                       ("chicken_feet", 0.84), ("steamed_bread", 0.81), ("chakalaka", 0.76),
                                                       ("leafy_greens", 0.69), ("bowl", 0.82), ("plate", 0.78)]

    func testOmeletteWithToastIsConfidentNotSpread() {
        XCTAssertEqual(PhotoGuess.assess(labels: Self.omeletteToast, ocrText: ""), .confident("omelette with toast"))
        if case .spread = PhotoGuess.assess(labels: Self.twoPlatesOmelette, ocrText: "") { XCTFail("two identical plates are one dish") }
    }
    func testChipsComeFromVisionNotTheFixedSAList() {
        let s = PhotoGuess.suggestions(labels: Self.omeletteToast, ocrText: "")
        XCTAssertEqual(s.first, "Omelette with Toast")
        XCTAssertTrue(s.contains("Omelette")); XCTAssertFalse(s.contains("Mogodu (tripe)"))
        XCTAssertTrue(PhotoGuess.suggestions(labels: [("food", 0.9), ("meal", 0.5)], ocrText: "").contains("Mogodu (tripe)"), "glossary only when ambiguous")
    }
    func testConfidenceCalibratedFromVision() {
        let c = PhotoGuess.calibratedConfidence(model: 0.1, title: "Omelette with Toast", labels: Self.omeletteToast) ?? 0
        XCTAssertGreaterThan(c, RecipeQuality.threshold)
        XCTAssertEqual(PhotoGuess.calibratedConfidence(model: 0.1, title: "Mogodu", labels: Self.omeletteToast), 0.1, "only when the card is what Vision saw")
    }
    func testSceneDescriptionGoesIntoThePrompt() {
        let d = PhotoGuess.sceneDescription(labels: Self.omeletteToast, salientObjects: 2, colours: ["yellow", "brown"])
        XCTAssertTrue(d.contains("omelette 71%")); XCTAssertTrue(d.contains("About 2 separate items")); XCTAssertTrue(d.contains("yellow"))
    }
    func testAmbiguousPhotoPromptSupportsDrinksWithoutInventingSpirits() {
        let prompt = RecipePrompt.photoUnnamed(labels: ["cocktail", "glass", "orange"], candidates: [], ocr: "")
        XCTAssertTrue(prompt.contains("drink/cocktail"))
        XCTAssertTrue(prompt.contains("specific spirit"))
        XCTAssertTrue(prompt.contains("colour or glassware alone"))
        XCTAssertTrue(prompt.contains("brandy, gin, vodka, rum or tequila"))
        XCTAssertTrue(prompt.contains("ask the user to identify the drink instead of inventing ingredients"))
    }
    func testSpringRollPhotoCannotUseAnUnlistedWrapper() {
        let c = RecipeCard(title: "Springroll", servings: 4, timeMinutes: 40,
                           ingredients: [.init(name: "vegetables mix", quantity: 100, unit: "g"),
                                         .init(name: "cumin", quantity: 2, unit: "tsp"),
                                         .init(name: "paprika", quantity: 1, unit: "tsp"),
                                         .init(name: "oil", quantity: 150, unit: "ml")],
                           steps: [.init(order: 1, instruction: "Mix the vegetables, cumin and paprika in a bowl", timeSeconds: 300),
                                   .init(order: 2, instruction: "Wrap the filling in pastry sheets", timeSeconds: 600),
                                   .init(order: 3, instruction: "Fry the spring rolls in hot oil until golden", timeSeconds: 900)],
                           source: .photoGuess)
        let gaps = RecipeQuality.shortfall(c)
        XCTAssertTrue(gaps.contains { $0.contains("Missing essentials") && $0.contains("spring roll wrapper") })
        XCTAssertTrue(gaps.contains { $0.contains("wrapping step") })
        XCTAssertTrue(RecipePrompt.photo(dish: "springroll", labels: [], ocr: "").contains("every visible structural component"))
    }
    // Cheese and polony sandwich device bug
    private func thinSandwich() -> RecipeCard {
        RecipeCard(title: "cheese and polony sandwich", servings: 4, timeMinutes: 30,
                   ingredients: [.init(name: "cheese", quantity: 2, unit: "slices"), .init(name: "polony", quantity: 3, unit: "slices")],
                   steps: [.init(order: 1, instruction: "Layer cheese and polony", timeSeconds: 120),
                           .init(order: 2, instruction: "Toast the sandwich in a pan over medium heat", timeSeconds: 300)],
                   source: .photoGuess)
    }
    func testLowConfidencePhotoAsksFirst() {
        var c = thinSandwich(); c.aiConfidence = 0.2
        XCTAssertTrue(RecipeQuality.shouldAskDish(c, alreadyConfirmed: false))
        XCTAssertEqual(RecipeQuality.guesses(c).first, "cheese and polony sandwich")
    }
    func testObjectTitleIsNeverARecipeDraft() {
        var c = thinSandwich(); c.title = "Utensil"; c.aiConfidence = 0.95
        XCTAssertTrue(RecipeQuality.isNonFoodTitle(c))
        XCTAssertTrue(RecipeQuality.issues(c).contains { $0.contains("edible dish") })
        XCTAssertTrue(RecipeQuality.needsInput(c))
    }
    func testThinPhotoRecipeTriggersRegenerationWithVisibleItems() {
        let labels = PhotoGuess.distinctFoods(Self.cheeseSandwich, minConfidence: 0.25).map(\.0)
        let gaps = RecipeQuality.shortfall(thinSandwich(), labels: labels)
        XCTAssertTrue(gaps.contains { $0.contains("at least 3 ingredients") })
        XCTAssertTrue(gaps.contains { $0.contains("at least 3 steps") })
        XCTAssertTrue(gaps.contains { $0.contains("bread") && $0.contains("lettuce") })
        XCTAssertFalse(gaps.contains { $0.contains("sandwich,") }, "the dish itself isn't an ingredient")
    }
    func testTotalTimeComesFromStepsPlusPrep() {
        let c = Durations.sanitize(thinSandwich()).card
        XCTAssertEqual(c.timeMinutes, 7 + 5, "7 min of steps + capped prep, not 30")
    }
    func testServingsInferredFromPhoto() {
        XCTAssertEqual(RecipeQuality.inferredServings(thinSandwich(), fromPhoto: true), 1)
        var tray = thinSandwich(); tray.title = "Party sandwiches platter"
        XCTAssertEqual(RecipeQuality.inferredServings(tray, fromPhoto: true), 4)
    }
    func testTitleCased() {
        XCTAssertEqual(RecipeLogic.normalize(thinSandwich()).title, "Cheese and Polony Sandwich")
        XCTAssertEqual(RecipeQuality.titleCased("Mac and cheese"), "Mac and cheese", "only all-lowercase titles change")
    }
}

/// Edit-screen regressions on a saved "sushi" recipe.
final class EditorRegressionTests: XCTestCase {
    private func sushi() -> RecipeCard {
        RecipeCard(title: "sushi", servings: 2, timeMinutes: 40, tags: ["condiment"],
                   ingredients: [.init(name: "sushi rice", quantity: 300, unit: "g"), .init(name: "seasonings", quantity: 1, unit: "")],
                   steps: [.init(order: 1, instruction: "Cook the rice", timeSeconds: 600),
                           .init(order: 2, instruction: "Season the rice", timeSeconds: 300),
                           .init(order: 3, instruction: "Roll the sushi", timeSeconds: 1500)],
                   source: .unknown)
    }
    func testStepTimesEditInMinutes() {
        XCTAssertEqual(StepMinutes.minutes(1500), 25); XCTAssertEqual(StepMinutes.minutes(nil), 0)
        XCTAssertEqual(StepMinutes.seconds(10), 600); XCTAssertNil(StepMinutes.seconds(0))
    }
    func testImplausibleRollingTimeIsDropped() {
        XCTAssertEqual(Durations.maximumSeconds(for: "Roll the sushi"), 600)
        XCTAssertNil(Durations.maximumSeconds(for: "Roll the dough and bake 20 minutes"))
        let c = Durations.sanitize(sushi()).card
        XCTAssertNil(c.steps[2].timeSeconds, "25 min of rolling with no time in the text isn't believable")
        XCTAssertEqual(c.steps[2].instruction, "Roll the sushi")
        XCTAssertEqual(Durations.sanitize(RecipeCard(steps: [.init(order: 1, instruction: "Roll for 25 minutes", timeSeconds: 1500)])).card.steps[0].timeSeconds, 1500)
    }
    func testThinSushiFailsQualityAndOffersImprove() {
        let i = RecipeQuality.issues(sushi())
        XCTAssertTrue(i.contains { $0.contains("nori") && $0.contains("rice vinegar") && $0.contains("a filling") })
        XCTAssertTrue(i.contains { $0.contains("seasonings") })
        XCTAssertTrue(i.contains { $0.contains("condiment") })
        XCTAssertTrue(i.contains { $0.contains("4 ingredients") })
        XCTAssertTrue(RecipeQuality.improvePrompt(sushi()).hasPrefix("Improve this recipe"))
    }
    func testSavedLowercaseTitleIsTitleCased() {
        XCTAssertEqual(RecipeLogic.normalize(sushi()).title, "Sushi")
        var manual = sushi(); manual.source = .manual
        XCTAssertEqual(RecipeLogic.normalize(manual).title, "sushi", "what the user typed is left alone")
    }
}
