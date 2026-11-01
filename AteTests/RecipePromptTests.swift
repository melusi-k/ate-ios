import XCTest
@testable import Ate

final class RecipePromptTests: XCTestCase {
    /// The real og:description of instagram.com/p/DOtb098DOM4 (2026-10-10): a delivery advert, no recipe, no dish name.
    static let midrandAd = "191 likes, 6 comments - cookingwith_ritshidze_foods on September 17, 2025: \"Have you tried our food yet?\n\nTraditional food for delivery in Midrand and surrounding areas 🤩\n\nText us on WhatsApp 061 588 3516\". "
    static let mogoduMenu = "88 likes, 3 comments - kasi_kitchen on 1 October 2026: \"Saturday special 🔥 Mogodu, ujeqe and morogo R85. Order on WhatsApp 071 234 5678 #mogodu #kasifood @kasi_kitchen\""
    static let recipeCaption = "1,204 likes, 40 comments - mzansi.eats on May 1, 2026: \"Chakalaka 🌶 You need 2 onions, 2 peppers, 3 carrots grated, 1 tin baked beans, 2 tsp curry powder. Fry onion 5 minutes, add the rest and simmer 20 minutes. Season to taste.\""

    func testStripsInstagramPrefixAndQuotes() {
        XCTAssertEqual(CaptionAnalysis.stripInstagramPrefix(Self.midrandAd),
                       "Have you tried our food yet?\n\nTraditional food for delivery in Midrand and surrounding areas 🤩\n\nText us on WhatsApp 061 588 3516")
        XCTAssertTrue(CaptionAnalysis.stripInstagramPrefix(Self.recipeCaption).hasPrefix("Chakalaka"))
        XCTAssertEqual(CaptionAnalysis.stripInstagramPrefix("Chef Thandi on Instagram: \"Creamy pasta\""), "Creamy pasta")
    }

    func testCaptionPrefersDescriptionOverTitle() {
        let meta = ["og:title": "Ritshidze Sibadali on Instagram: \"Have you tried our food yet?\"", "og:description": Self.midrandAd]
        let c = SocialLinks.caption(platform: .instagram, oEmbed: nil, meta: meta)
        XCTAssertFalse(c.contains("likes")); XCTAssertFalse(c.contains("Ritshidze Sibadali on Instagram"))
        XCTAssertTrue(c.hasPrefix("Have you tried our food yet?"))
    }

    func testAdvertWithoutDishIsUngrounded() {
        XCTAssertTrue(CaptionAnalysis.isUngroundedPromo(Self.midrandAd))
        XCTAssertFalse(CaptionAnalysis.isUngroundedPromo(Self.mogoduMenu), "names a dish")
        XCTAssertFalse(CaptionAnalysis.isUngroundedPromo(Self.recipeCaption), "is a recipe")
    }

    func testScrubRemovesHandlesHashtagsPhones() {
        let s = CaptionAnalysis.scrub(CaptionAnalysis.stripInstagramPrefix(Self.mogoduMenu))
        XCTAssertFalse(s.contains("@")); XCTAssertFalse(s.contains("#")); XCTAssertFalse(s.contains("071 234 5678"))
        XCTAssertTrue(s.contains("Mogodu, ujeqe and morogo"))
    }

    func testGlossaryMatches() {
        let names = CuisineGlossary.matches(in: "Mogodu, ujeqe and morogo").map(\.name)
        XCTAssertEqual(names, ["Ujeqe (steamed bread)", "Mogodu / ulusu (tripe)", "Morogo"])
        XCTAssertEqual(CuisineGlossary.matches(in: "samp and beans tonight").first?.name, "Umngqusho (samp and beans)")
        XCTAssertTrue(CuisineGlossary.matches(in: "Midrand delivery").isEmpty)
        XCTAssertGreaterThanOrEqual(CuisineGlossary.dishes.first { $0.name.hasPrefix("Mogodu") }!.minutes, 120)
    }

    /// Prompt snapshot: change deliberately, then update the expected text.
    func testSocialPromptSnapshot() {
        let p = RecipePrompt.social(caption: Self.mogoduMenu)
        let expected = """
        Social media caption (the only source of truth):
        \"\"\"
        Saturday special 🔥 Mogodu, ujeqe and morogo R85. Order on WhatsApp
        \"\"\"
        This caption looks like an advert or menu, not a recipe. Only use dish names that appear in it.
        Regional dishes mentioned: Ujeqe (steamed bread); Mogodu / ulusu (tripe); Morogo.

        """
        XCTAssertEqual(p, expected)
    }

    func testInstructionsForbidHallucination() {
        let i = RecipePrompt.instructions
        for must in ["Never use place names", "hashtags", "@handles", "NAMED dish", "Unknown dish", "metric", "tripe takes 2 to 3 h", "confidence"] {
            XCTAssertTrue(i.contains(must), must)
        }
    }

    /// Consolidation guard: each critical rule is stated exactly once in the shared instructions,
    /// so a future edit cannot silently drop it or reintroduce the duplication the review found.
    func testCriticalRulesAppearExactlyOnce() {
        let i = RecipePrompt.instructions
        for phrase in ["First identify the dish", "confidence below 0.2", "Do not invent a different dish", "call lookupRegionalDish"] {
            XCTAssertEqual(i.components(separatedBy: phrase).count - 1, 1, phrase)
        }
        let u = RecipePrompt.photoUnnamed(labels: [], candidates: [], ocr: "")
        XCTAssertEqual(u.components(separatedBy: "Unknown dish").count - 1, 1, "photoUnnamed states the Unknown-dish fallback once")
        XCTAssertEqual(u.components(separatedBy: "confidence below 0.2").count - 1, 1)
    }

    /// instructions(for:) is the shared block plus exactly this brief. Snapshot per mode:
    /// change deliberately, then update the expected text.
    func testPerModeBriefSnapshots() {
        let briefs: [(RecipePrompt.Input, String)] = [
            (.link, "Input: text scraped from a recipe web page. Ignore navigation, ads and comments."),
            (.social, "Input: a social media caption. It may be an advert or menu; follow rule 3 and 4 strictly."),
            (.photo, "Input: a photo of food or a beverage, optionally named by the user. If you need printed text in the photo (menu boards, labels), call readPhotoText. Distinguish plated food from a drink/cocktail only when image labels and scene clues support it. A glass, plate, utensil, wooden object, cookware or tableware alone is not enough to identify a recipe."),
            (.screenshot, "Input: OCR text of a recipe screenshot. Keep the original quantities and order."),
            (.prompt, "Input: the user's own description. A sensible traditional recipe is fine; still follow the units and timing rules."),
            (.rewrite, "Input: an existing recipe card as JSON plus the user's change request. Change only what is asked."),
        ]
        XCTAssertEqual(briefs.count, 6, "one brief per input mode")
        for (input, brief) in briefs {
            XCTAssertEqual(RecipePrompt.instructions(for: input), RecipePrompt.instructions + "\n" + brief, "\(input)")
        }
    }

    /// Prompt-size guard (measured characters; the on-device window is 4,096 tokens per Apple TN3193,
    /// roughly 3-4 characters per token). Consolidation savings must stay saved.
    /// Raise only with a deliberate, reviewed prompt change.
    func testPromptSizeGuard() {
        XCTAssertLessThanOrEqual(RecipePrompt.instructions.count, 3450, "shared instructions grew (measured 3,433 after the Nov 2026 consolidation)")
        for input in [RecipePrompt.Input.link, .social, .photo, .screenshot, .prompt, .rewrite] {
            XCTAssertLessThanOrEqual(RecipePrompt.instructions(for: input).count, 3900, "instructions(for: \(input)) grew")
        }
        let u = RecipePrompt.photoUnnamed(labels: ["food", "bowl"], candidates: ["Mogodu (tripe)"], ocr: "menu text")
        XCTAssertLessThanOrEqual(u.count, 1600, "photoUnnamed assembled body grew")
    }

    /// Dietary/servings cues come from attributable text (the user's own words, the scraped source),
    /// never the assembled prompt's examples or guidance.
    func testContextFromScrapedSourceText() {
        let c = RecipePrompt.context(userText: "https://instagram.com/p/xyz", sourceText: "Vegan chakalaka for 6", sourceIsLongForm: false, region: "ZA")
        XCTAssertEqual(c.dietary, ["vegan"]); XCTAssertEqual(c.servings, 6); XCTAssertEqual(c.region, "South Africa")
    }

    /// Cooking times are not servings; negated diets are not requirements (even with sloppy spacing).
    func testContextIgnoresTimeUnitsAndNegation() {
        XCTAssertNil(RecipePrompt.context(for: "Simmer for 20 minutes, then bake for 2 hours.").servings)
        XCTAssertNil(RecipePrompt.context(for: "Rest for 30 min, then bake for 2h.").servings)
        XCTAssertEqual(RecipePrompt.context(for: "Serves 8.").servings, 8)
        XCTAssertEqual(RecipePrompt.context(for: "Dinner for 2 people").servings, 2)
        XCTAssertEqual(RecipePrompt.context(for: "chakalaka for 6").servings, 6)
        XCTAssertEqual(RecipePrompt.context(for: "not vegan at all").dietary, [])
        XCTAssertEqual(RecipePrompt.context(for: "definitely not  vegan, thanks").dietary, [])
        XCTAssertEqual(RecipePrompt.context(for: "isn't vegan").dietary, [])
        XCTAssertEqual(RecipePrompt.context(for: "never vegetarian tonight").dietary, [])
        XCTAssertEqual(RecipePrompt.context(for: "non-vegan").dietary, [])
        XCTAssertEqual(RecipePrompt.context(for: "make it vegan").dietary, ["vegan"])
        XCTAssertEqual(RecipePrompt.context(for: "Vegan!").dietary, ["vegan"])
        XCTAssertEqual(RecipePrompt.context(for: "a knot in the vegan thread").dietary, ["vegan"], "'knot' is not a negator")
    }

    /// Explicit user text wins over the scraped recipe; a stated dietary identity applies even on long pages.
    func testContextPriorityUserOverSource() {
        let c = RecipePrompt.context(userText: "chakalaka for 2", sourceText: "Serves 8. Vegan.", sourceIsLongForm: true, region: "US")
        XCTAssertEqual(c.servings, 2, "the user's explicit servings win over the page")
        XCTAssertEqual(c.dietary, ["vegan"], "the page states vegan as the dish's identity (title region)")
        let d = RecipePrompt.context(userText: "", sourceText: "Serves 8. Vegan.", sourceIsLongForm: false, region: "US")
        XCTAssertEqual(d.servings, 8); XCTAssertEqual(d.dietary, ["vegan"])
    }

    /// Long full-recipe sources: a diet counts when the recipe states it as its identity or
    /// requirement, never as an optional adaptation; negations never count.
    func testSourceDietaryStatedIdentityOnly() {
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Vegan Mac and Cheese\n\nA creamy cashew sauce makes this a favourite.", longForm: true), ["vegan"], "title region states the identity")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Mac and Cheese\n\nThis recipe is naturally gluten-free and feeds a crowd.", longForm: true), ["gluten-free"], "requirement phrasing counts")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Mac and Cheese\n\nA family favourite. To make it vegan, swap the butter for oil and use a dairy-free cheese alternative.", longForm: true), [], "optional adaptations are not requirements")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "A rich stew. Not vegan, but easily adapted with beans.", longForm: true), [], "negated mentions are not requirements")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Definitely not  vegan, sadly.", longForm: false), [], "sloppy spacing still negates")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Sunday lunch sorted: vegan chakalaka and rice!", longForm: false), ["vegan"], "short dish-defining sources count a plain mention")
        XCTAssertEqual(RecipePrompt.sourceDietary(in: "Love this? Try our vegetarian version next week.", longForm: false), [], "advert-style alternatives are not the dish")
    }

    /// Dietary precedence: an explicit user requirement wins outright; a scraped identity yields to
    /// the dish the user actually asked for (no blind union).
    func testDietaryPrecedenceAndConflicts() {
        let c = RecipePrompt.context(userText: "chicken curry for supper", sourceText: "Easy vegan curry", sourceIsLongForm: false, region: "ZA")
        XCTAssertEqual(c.dietary, [], "explicit 'chicken' contradicts the caption's 'vegan'; the user's dish wins")
        let v = RecipePrompt.context(userText: "make it vegetarian please", sourceText: "Vegan lentil soup", sourceIsLongForm: false, region: "US")
        XCTAssertEqual(v.dietary, ["vegetarian"], "an explicit user requirement wins outright")
        let g = RecipePrompt.context(userText: "add cheese", sourceText: "Dairy-free mac", sourceIsLongForm: false, region: "US")
        XCTAssertEqual(g.dietary, [], "explicit 'cheese' contradicts 'dairy-free'")
    }

    /// The retry tells the same-session model exactly what to repair.
    func testRetryInstructionCarriesGapsAndVisibleLabels() {
        let s = RecipePrompt.retryInstruction(gaps: ["Needs at least 3 ingredients."], visibleLabels: ["bread", "lettuce"])
        XCTAssertTrue(s.contains("previous draft fell short")); XCTAssertTrue(s.contains("Needs at least 3 ingredients."))
        XCTAssertTrue(s.contains("bread, lettuce")); XCTAssertTrue(s.hasSuffix("Return the corrected card."))
        XCTAssertFalse(RecipePrompt.retryInstruction(gaps: ["g"], visibleLabels: []).contains("visible component"))
    }

    func testPhotoAssessment() {
        let generic: [(String, Float)] = [("food", 0.9), ("potato", 0.4), ("meal", 0.5)]
        guard case .uncertain(let s) = PhotoGuess.assess(labels: generic, ocrText: "") else { return XCTFail("generic labels must ask") }
        XCTAssertTrue(s.contains("Mogodu (tripe)"))
        let spread: [(String, Float)] = [("food", 0.9), ("bowl", 0.7), ("pizza", 0.6), ("sushi", 0.5), ("hamburger", 0.45), ("rice", 0.4)]
        guard case .spread = PhotoGuess.assess(labels: spread, ocrText: "") else { return XCTFail("3+ different foods = spread") }
        let bowls: [(String, Float)] = [("food", 0.9), ("bowl", 0.7), ("tableware", 0.6), ("stew", 0.4), ("bread", 0.3)]
        if case .spread = PhotoGuess.assess(labels: bowls, ocrText: "") { XCTFail("bowls/plates alone are not a spread") }
        XCTAssertEqual(PhotoGuess.assess(labels: [("pizza", 0.85), ("food", 0.9)], ocrText: ""), .confident("pizza"))
        XCTAssertEqual(PhotoGuess.assess(labels: generic, ocrText: "Mogodu Saturday"), .confident("Mogodu / ulusu (tripe)"))
        let p = RecipePrompt.photo(dish: "ujeqe", labels: ["bread"], ocr: "")
        XCTAssertTrue(p.contains("exactly that dish"))
        XCTAssertTrue(RecipePrompt.instructions(for: .photo).contains("lookupRegionalDish"), "tool instruction lives once in the shared instructions")
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("ujeqe").contains("steam 1 h"), "glossary detail now comes from the tool")
    }
    /// Cooking times are not servings; negated diets are not requirements (even with sloppy spacing).

}

