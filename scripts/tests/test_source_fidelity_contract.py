from verified_paste_import_delta import restore as pre_simplification
"""Link/pasted-recipe extraction must stay bound to the source's own facts."""
from pathlib import Path
import hashlib, unittest
ROOT = Path(__file__).resolve().parents[2]

class SourceFidelityContractTests(unittest.TestCase):
    def test_generation_quality_gates_and_prompt_are_byte_identical(self):
        # No weakened checks and no prompt change: the fix is a deterministic gate,
        # not looser validation or different instructions.
        pins = {
                'Ate/Logic/ScreenshotRecipeImport.swift': '4d8393c7fd4847dcc5ed5feccc02484535c6db507c108726dc3f4ffd9f2dc994',
                'Ate/Logic/GeneratedRecipeConsistency.swift': '85fd238b9baa73d3fa16755f4e70a010639f5558d973741e49a69c07b424ef76'}
        for path, expected in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected, path)
        # fix/advisory-gap-no-autorepair: GeneratedStepQuality gains the advisory
        # unused-ingredient gap classifier (shared suffix constant + predicate), and the
        # producer appends via the constant (byte-identical gap text). Assert the new
        # contract, then inverse-remove the exact additions and verify the original
        # remainder hash (no hash replacement).
        g = (ROOT/'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('static let unusedIngredientGapSuffix = "it is listed but never used in the steps."', g)
        self.assertIn('gaps.append("Explain when to use \\(ingredient.name); \\(unusedIngredientGapSuffix)")', g)
        self.assertIn('static let implicitStaples: Set<String> = ["salt", "black pepper", "pepper", "water",\n                                               "cooking oil", "oil", "olive oil",\n                                               "vegetable oil", "sunflower oil"]', g)
        g = g.replace('''    /// Advisory class: an unused IMPLICIT STAPLE whose exact normalized name is on
    /// this closed list. Only plain staple names count: "chicken in water", "beef
    /// stock with salt" or "rice flour" name main foods and are never advisory, and
    /// flour, sugar and butter are NOT advisory at all, so a cake that never uses
    /// its flour still repairs automatically. An advisory gap is listed on the
    /// review card with a manual Repair option, and on its own never triggers the
    /// automatic repair pass, which costs a second full on-device generation. An
    /// unused main ingredient is a real gap and still repairs automatically.
    /// Producer and classifier share this suffix so they cannot drift.
    static let unusedIngredientGapSuffix = "it is listed but never used in the steps."
    static let implicitStaples: Set<String> = ["salt", "black pepper", "pepper", "water",
                                               "cooking oil", "oil", "olive oil",
                                               "vegetable oil", "sunflower oil"]
    static func isImplicitStapleGap(_ gap: String) -> Bool {
        let prefix = "Explain when to use "
        guard gap.hasPrefix(prefix), gap.hasSuffix(unusedIngredientGapSuffix) else { return false }
        let name = gap.dropFirst(prefix.count).dropLast(unusedIngredientGapSuffix.count + 2)
        let normalized = String(name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return implicitStaples.contains(normalized)
    }
''','',1)
        g = g.replace('''gaps.append("Explain when to use \\(ingredient.name); \\(unusedIngredientGapSuffix)")''','''gaps.append("Explain when to use \\(ingredient.name); it is listed but never used in the steps.")''',1)
        self.assertEqual(hashlib.sha256(g.encode()).hexdigest(),'ac7390197516646d490207f1f3527abed9ca27d7e7405e61d8e4d91fc0d07762','Ate/Logic/GeneratedStepQuality.swift inverse remainder')
        # fix/445-insights-discovery (#535): RecipeQuality gains an explicit empty-ingredients
        # gate for generated recipes. Assert the new gate, then inverse-remove the exact
        # addition and verify the original remainder hash (no hash replacement).
        from prompt_draft_boundary_delta import restore
        q = restore('Ate/Logic/RecipeQuality.swift', (ROOT/'Ate/Logic/RecipeQuality.swift').read_text())
        self.assertIn('if c.ingredients.isEmpty {', q)
        self.assertIn('out.append("The generated recipe needs measured ingredients.")', q)
        q = q.replace('''            // A cold dish can use foods outside the bounded step vocabulary.
            // An empty list is still incomplete, regardless of dish category.
            if c.ingredients.isEmpty {
                out.append("The generated recipe needs measured ingredients.")
            }
''','',1)
        # fix/advisory-gap-no-autorepair: RecipeQuality gains gapsNeedingRepair, the
        # automatic-repair partition. Assert the new helper, then inverse-remove the
        # exact addition before the remainder hash (no hash replacement).
        self.assertIn('static func gapsNeedingRepair(_ gaps: [String]) -> [String]', q)
        self.assertIn('gaps.filter { !GeneratedStepQuality.isImplicitStapleGap($0) }', q)
        q = q.replace('''    /// The gaps that trigger the automatic repair pass. The advisory
    /// unused-implicit-staple class (the closed exact-name list: salt, black
    /// pepper, pepper, water and the cooking oils) never does on its own: the
    /// review card already lists it with a manual Repair button, and an
    /// automatic repair costs a second full on-device generation. An unused
    /// main ingredient (flour in a cake included) and every other gap
    /// (structure, times, doneness, consistency, fidelity) still repair
    /// automatically. The review card's gap list itself is unchanged:
    /// shortfall/issues keep returning every gap.
    static func gapsNeedingRepair(_ gaps: [String]) -> [String] {
        gaps.filter { !GeneratedStepQuality.isImplicitStapleGap($0) }
    }

''','',1)
        self.assertEqual(hashlib.sha256(q.encode()).hexdigest(),'1b3f3b824baa39e50aebd138f9f583f4321f762079e60328c6bb4f28de163de4')
        # fix/445-library-pork (#536): the generation prompt gains source-preserving
        # protein species/cut guidance and the South African persona (in the branch's
        # evidence boundary). Assert the new guidance, then inverse-restore the original
        # prompt and verify the original hash (no hash replacement).
        c = (ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        for token in ['Preserve source protein species/cut',
                      'never relabel beef/lamb ribs as pork',
                      'list primary first by largest comparable quantity']:
            self.assertIn(token, c)
        c=c.replace('/// Pure prompt construction for Foundation Models (snapshot-tested in RecipePromptTests).\nenum RecipePrompt {\n    static let instructions = """\n    South African home-cooking expert, also Southern/West African and international. Turn input into one recipe card.\n    First identify the dish (dishName, cuisine, confidence, alternatives), then recipe: title, servings, time, ingredients (amount, unit, name, prep), steps (instruction, minutes, temperatureC). confidence = 0 to 1 certainty in dishName; below 0.8 if not clearly named or shown.\n    Rules:\n    1. Ground everything in the input; copy given dish names and ingredients verbatim. Do not invent a different dish or drink.\n    2. Never use place names, business or account names, hashtags, @handles, phone numbers, prices or delivery/ordering text as the dish, title or ingredients.\n    3. For a menu/advert naming a dish without a recipe, write a best-effort traditional recipe for that NAMED dish; disclose in note.\n    4. If no dish is named (text) or established by visible evidence/image labels (photo), use title "Unknown dish", confidence below 0.2; explain in note. Never infer a specific ingredient/recipe from ambiguous colour, glass or objects.\n    Preserve source protein species/cut (pork ribs, pork belly, bacon, pork chops, beef ribs, chicken wings); never relabel beef/lamb ribs as pork. Keep source amounts; do not guess weights for counted pieces. For generated mixed proteins, list primary first by largest comparable quantity. Library categories come from ingredients, not invented tags.\n    5. Use realistic home amounts in metric units (g, kg, ml, l, tbsp, tsp, cloves, pcs); suitable servings (stews/braises usually 4 to 6).\n    6. Give waiting/cooking minutes matching written times ("2 to 3 h" is 180). timeMinutes = step sum + prep; note any added "Prep: N min". tripe takes 2 to 3 h, steamed bread over 1 h, samp and beans 2 to 3 h.\n    7. Respect South African, Southern African and West African cuisines. For regional/unfamiliar dish names, call lookupRegionalDish before ingredients. Never substitute an unrelated Western dish.\n    8. A main dish needs at least 4 real ingredients with quantities; oven steps give °C. Include needed prep, heat, time, doneness, transitions and appropriate serving/resting; no filler or skipped actions. Times: simmer/stew 20+ min, braise 1 h+, pap 15+ min, browning 5+ min. Use specific verbs, not just "cook the ribs". No source-contradicting steps or ingredients.\n    9. Reconcile ingredients and steps both ways: measure each used item and use each listed item, including salt, oil, water, bread, wrappers and filling. Preserve dish-defining structure. In generated curries, aromatics/spices precede simmering; explain pre-boil liquid handling. Preserve source order; flag gaps, don\'t invent missing source facts.\n    Example 1 (South African), input "chakalaka": dish Chakalaka, South African, confidence 0.95. Ingredients: 2 tbsp oil; 1 onion, diced; 2 carrots, grated; 1 green pepper, diced; 2 tsp curry powder; 400 g tinned baked beans. Steps: Sauté the onion in the oil over medium heat until soft, 5 min. Stir in the carrot, pepper and curry powder and fry 3 min. Add the beans and simmer uncovered until thick, 15 min.\n    Example 2, input "sticky oven ribs": dish Sticky pork ribs, American, confidence 0.9. Ingredients: 1.2 kg pork ribs; 3 tbsp brown sugar; 2 tsp smoked paprika; 3 cloves garlic, crushed; 125 ml barbecue sauce. Steps: Rub the ribs with sugar, paprika and garlic. Wrap in foil and bake at 160°C until tender, 120 min. Unwrap, brush with sauce and roast at 220°C until sticky, 15 min.\n    """','/// Pure prompt construction for Foundation Models (snapshot-tested in RecipePromptTests).\nenum RecipePrompt {\n    static let instructions = """\n    You are a South African home-cooking expert who also knows Southern and West African, and international, home cooking. You turn the user\'s input into one recipe card.\n    Format: First identify the dish (dishName, cuisine, confidence, alternatives), then write the recipe for that dish: title, servings, time, ingredients (amount, unit, name, prep) and steps (instruction, minutes, temperatureC). confidence is 0 to 1: how sure you are about dishName; use below 0.8 when the input does not clearly name or show it.\n    Rules:\n    1. Ground everything in the provided text. Copy dish names and ingredients verbatim when they are given. Do not invent a different dish or drink than the input names or shows.\n    2. Never use place names, business or account names, hashtags, @handles, phone numbers, prices or delivery/ordering text as the dish, title or ingredients.\n    3. If the text is a menu or an advert that names a dish but has no recipe, write a best-effort traditional recipe for that NAMED dish and say so in note.\n    4. If no dish is named (text) or the item cannot be established from visible evidence and image labels (photo), title the card "Unknown dish", set confidence below 0.2 and explain in note. Never turn an ambiguous colour, glass or object into a specific ingredient or recipe.\n    5. Use realistic home quantities in metric units (g, kg, ml, l, tbsp, tsp, cloves, pcs). Servings must suit the dish (stews and braises usually 4 to 6).\n    6. Give minutes for waiting/cooking, matching written times ("2 to 3 h" is 180). timeMinutes = step sum + prep; put "Prep: N min" in note for any added prep. tripe takes 2 to 3 h, steamed bread over 1 h, samp and beans 2 to 3 h.\n    7. Respect regional cuisines (South African, Southern African, West African). For any regional or unfamiliar dish name, call lookupRegionalDish before writing ingredients. Never replace them with an unrelated Western dish.\n    8. A main dish needs at least 4 real ingredients with quantities; oven steps give °C. Include needed prep, heat, time and doneness cues, transitions and serving/resting only when appropriate. No filler or skipped actions. Times: simmer/stew 20+ min, braise 1 h+, pap 15+ min, browning 5+ min. Use specific verbs, never just "cook the ribs". Never invent steps or ingredients the source contradicts.\n    9. Reconcile ingredients and steps both ways, including salt, oil, water, bread, wrappers and filling. Measure every item used; use every item listed. Preserve dish-defining structure, not just its name. Order dependencies: aromatics/spices before simmering a generated curry; explain any pre-boil liquid. Preserve source order; flag gaps, don\'t invent missing source facts.\n    Example 1 (South African), input "chakalaka": dish Chakalaka, South African, confidence 0.95. Ingredients: 2 tbsp oil; 1 onion, diced; 2 carrots, grated; 1 green pepper, diced; 2 tsp curry powder; 400 g tinned baked beans. Steps: Sauté the onion in the oil over medium heat until soft, 5 min. Stir in the carrot, pepper and curry powder and fry 3 min. Add the beans and simmer uncovered until thick, 15 min.\n    Example 2, input "sticky oven ribs": dish Sticky pork ribs, American, confidence 0.9. Ingredients: 1.2 kg pork ribs; 3 tbsp brown sugar; 2 tsp smoked paprika; 3 cloves garlic, crushed; 125 ml barbecue sauce. Steps: Rub the ribs with sugar, paprika and garlic. Wrap in foil and bake at 160°C until tender, 120 min. Unwrap, brush with sauce and roast at 220°C until sticky, 15 min.\n    """',1)
        # fix/pasted-recipe-source-binding: prompt()/social() no longer clip the
        # source; inverse-restore both before the byte-exact hash.
        c=c.replace('        // The source reaches the model whole: a silent clip invents the rest.\n        var p = "Social media caption (the only source of truth):\\n\\"\\"\\"\\n\\(caption)\\n\\"\\"\\"\\n"','        var p = "Social media caption (the only source of truth):\\n\\"\\"\\"\\n\\(caption.prefix(3000))\\n\\"\\"\\"\\n"',1)
        c=c.replace('        // Never clip the user\'s text: a truncated paste becomes an invented recipe.\n        // Over-long pastes fail closed in OnDeviceBackend before reaching here.\n        "Recipe card for: \\(text)\\n" + glossary(for: text)','        "Recipe card for: \\(text.prefix(500))\\n" + glossary(for: text)',1)
        # Packet D r3: page() no longer clips (the caller feeds the verified contract's
        # own text, or a bounded head for an uncertified page). Assert the new body,
        # then inverse-restore the exact r2 body before the remainder hash.
        self.assertIn('"Web page text:\\n\\"\\"\\"\\n\\(text)\\n\\"\\"\\"\\nExtract the recipe from it.\\n" + glossary(for: text)', c)
        c = c.replace('''    static func page(_ text: String) -> String {
        // Never clip here: the caller chooses and bounds the text (the verified
        // contract's own text when one exists), and a silent cut drops recipe
        // lines that start past the cap, so the model invents the rest.
        "Web page text:\\n\\"\\"\\"\\n\\(text)\\n\\"\\"\\"\\nExtract the recipe from it.\\n" + glossary(for: text)
    }
''','''    static func page(_ text: String) -> String {
        "Web page text:\\n\\"\\"\\"\\n\\(text.prefix(3500))\\n\\"\\"\\"\\nExtract the recipe from it.\\n" + glossary(for: text)
    }
''',1)
        self.assertEqual(hashlib.sha256(c.encode()).hexdigest(),'bc05a5a047f5542df6aee8bfa3e831fb625ff8a74af6c452c8a611a91194f558')

    def test_structured_contract_parses_only_explicit_measured_sections(self):
        s = (ROOT/'Ate/Logic/SourceRecipeFidelity.swift').read_text()
        self.assertEqual(s.count('static func structuredRecipe(_ raw: String) -> Contract?'), 1)
        self.assertEqual(s.count('static func claimsStructuredRecipe(_ raw: String) -> Bool'), 1)
        self.assertEqual(s.count('static func extraction(_ raw: String) -> Extraction'), 1)
        for token in [r'\bingredients\b\s*:?', r'\b(?:method|directions|instructions)\b\s*:?',
                      'CaptionAnalysis.hasRecipeSignals(method)',
                      # A second concatenated recipe makes every boundary ambiguous: refuse.
                      r'\bingredients\b\s*:?\s*\d',
                      # Whole-item quantity round-trip, positive amounts, unique names.
                      'amount == ingredient.quantity',
                      'Set(ingredients.map { $0.name.lowercased() }).count == ingredients.count',
                      # Prose, interior headings and unmeasured amounts are never
                      # certified as a verified item. Ambiguity absorbed into the
                      # name is refused by name guards; comma/parenthesis tails are
                      # a closed prep-word whitelist, not a blacklist of bad tails.
                      'let remainder = ns.substring(with: match.range(at: 2))',
                      'itemTails.allSatisfy(isPrepOnly)',
                      'static func isPrepOnly(_ tail: String) -> Bool',
                      'static func tails(in remainder: String) -> [String]',
                      '"cut into strips"',
                      r'\b(?:to taste|as needed|as required|optional)\b',
                      '.count <= 3']:
            self.assertIn(token, s)
        # No structure vs recognizable-but-unverifiable structure are distinct outcomes,
        # for section-marked recipes AND for recognizable "you need" captions alike.
        for token in ['case none', 'case verified(Contract)', 'case unverifiable',
                      'static func claimsInlineCaption(_ raw: String) -> Bool',
                      'if let contract = inlineCaption(raw) ?? structuredRecipe(raw) ?? multiPartRecipe(raw) ?? captionSections(raw) { return .verified(contract) }',
                      'return claimsStructuredRecipe(raw) || claimsInlineCaption(raw) || claimsCaptionSections(raw) || isRecipeShaped(raw) ? .unverifiable : .none']:
            self.assertIn(token, s)
        # Line boundaries are the only defensible item boundary: only spaces/tabs
        # collapse, and ALL multi-item shared lines are refused (one item per line).
        for token in ['#"[ \\t]+"#', 'guard split.count == 1 else { return nil }',
                      'itemTails.allSatisfy(isPrepOnly)']:
            self.assertIn(token, s)
        # htmlToText preserves list/br/block boundaries as newlines so real pages certify.
        b = (ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for token in ['"<br[^>]*>"', '"<li[^>]*>"', 'joined(separator: "\\n")']:
            self.assertIn(token, b)
        # Title stays the source's dish: named dish must survive; no invented title foods.
        for token in ['let dishes: [String]',
                      'CuisineGlossary.matches(in: String(header.suffix(200)))',
                      'do not invent a different title',
                      'GeneratedStepQuality.words(card.title).intersection(GeneratedStepQuality.foods)',
                      'which the source never mentions']:
            self.assertIn(token, s)
        # A parenthesis cannot hide an unmeasured item inside a measured caption part:
        # caption tails run through the same prep-word whitelist. A caption that names
        # its dish binds the title (glossary or a verbatim first-line name); a caption
        # naming nothing keeps the honest Unknown-dish path and the user question.
        self.assertIn('guard let quantity = part.range(of: #"^\\d+(?:[./]\\d+)?\\s+"#', s)
        self.assertIn('tails(in: String(part[quantity.upperBound...])).allSatisfy(isPrepOnly)', s)
        self.assertIn('let captionHeader = String(source[..<marker.lowerBound])', s)
        self.assertIn('if let named = captionDishName(captionHeader)', s)
        self.assertIn('return Contract(text: source, ingredients: ingredients, method: method, dishes: dishes)', s)
        self.assertIn('return Contract(text: text, ingredients: ingredients, method: method, dishes: dishes)', s)

    def test_backend_binds_link_and_pasted_sources_and_fails_closed(self):
        s = pre_simplification('Ate/Services/OnDeviceBackend.swift',(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text())
        for token in ['var structuredSource: SourceRecipeFidelity.Contract?',
                      'var unverifiableSource = false',
                      # One shared pre-model recognition step covers all three extraction inputs.
                      'SourceRecipeFidelity.extraction(request.text ?? "")',
                      'SourceRecipeFidelity.extraction(caption)',
                      'SourceRecipeFidelity.extraction(Self.htmlToText(html))',
                      'fidelity = structuredSource ?? SourceRecipeFidelity.structuredRecipe(pageText)',
                      # Recognizable-but-unverifiable structure never reaches demo or creative generation.
                      "could not be verified. No demo recipe was substituted",
                      "Ate couldn't verify this recipe's ingredients and method. No recipe was generated."]:
            self.assertIn(token, s)
        # The fail-closed terminal gate and one repair pass are retained, not bypassed.
        self.assertIn("Ate couldn't preserve this recipe's source quantities, ingredients or times. No card was accepted.", s)
        self.assertIn("No demo recipe was substituted", s)
        self.assertEqual(s.count('RecipeDraftRepair.automaticImproves'), 1)

    def test_native_coverage_names_the_reported_failure(self):
        t = (ROOT/'AteTests/SourceRecipeFidelityTests.swift').read_text()
        for token in ['testStructuredPageRoundTripsItsOwnFactsWithoutCreativeSubstitution',
                      'testStructuredPageRejectsInventedDishAndRenamedIngredients',
                      'testStructuredPageTimesCannotBeShortenedReorderedDroppedOrInvented',
                      'testTitleFoodNounsMustAppearInSourceEvenWithoutKnownDish',
                      'testAmbiguousPageStructureIsNotPartiallyCertified',
                      'testRecognizableButUnverifiableStructureIsDistinguishedFromNoStructure',
                      'testStructuredCaptionIsRecognizedByTheSharedPreModelStep',
                      'testPastedMultilineRecipeParsesLikeAPage',
                      'testPastedStructuredRecipeDoesNotSubstituteDemoWhenModelIsUnavailable',
                      'testUnverifiableStructureFailsClosedBeforeCreativeGenerationOrDemo',
                      'testStructuredPageDoesNotSubstituteDemoWhenModelIsUnavailable',
                      'salt to taste',
                      'Creamy Paprika Beef Pasta']:
            self.assertIn(token, t)

if __name__ == '__main__':
    unittest.main()
