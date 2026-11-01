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
        Regional dishes mentioned: Ujeqe (steamed bread); Mogodu / ulusu (tripe); Morogo. Call lookupRegionalDish for each before writing ingredients.

        """
        XCTAssertEqual(p, expected)
    }

    func testInstructionsForbidHallucination() {
        let i = RecipePrompt.instructions
        for must in ["Never use place names", "hashtags", "@handles", "NAMED dish", "Unknown dish", "metric", "tripe takes 2 to 3 h", "confidence"] {
            XCTAssertTrue(i.contains(must), must)
        }
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
        XCTAssertTrue(p.contains("exactly that dish")); XCTAssertTrue(p.contains("lookupRegionalDish"))
        XCTAssertTrue(RecipePrompt.lookupRegionalDish("ujeqe").contains("steam 1 h"), "glossary detail now comes from the tool")
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

}

