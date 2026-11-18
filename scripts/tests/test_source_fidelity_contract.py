"""Link/pasted-recipe extraction must stay bound to the source's own facts."""
from pathlib import Path
import hashlib, unittest
ROOT = Path(__file__).resolve().parents[2]

class SourceFidelityContractTests(unittest.TestCase):
    def test_generation_quality_gates_and_prompt_are_byte_identical(self):
        # No weakened checks and no prompt change: the fix is a deterministic gate,
        # not looser validation or different instructions.
        pins = {'Ate/Logic/RecipePrompt.swift': 'bc05a5a047f5542df6aee8bfa3e831fb625ff8a74af6c452c8a611a91194f558',
                'Ate/Logic/GeneratedStepQuality.swift': 'ac7390197516646d490207f1f3527abed9ca27d7e7405e61d8e4d91fc0d07762',
                'Ate/Logic/RecipeQuality.swift': '1b3f3b824baa39e50aebd138f9f583f4321f762079e60328c6bb4f28de163de4',
                'Ate/Logic/ScreenshotRecipeImport.swift': '4d8393c7fd4847dcc5ed5feccc02484535c6db507c108726dc3f4ffd9f2dc994',
                'Ate/Logic/GeneratedRecipeConsistency.swift': '85fd238b9baa73d3fa16755f4e70a010639f5558d973741e49a69c07b424ef76'}
        for path, expected in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected, path)

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
                      'if let contract = inlineCaption(raw) ?? structuredRecipe(raw) { return .verified(contract) }',
                      'return claimsStructuredRecipe(raw) || claimsInlineCaption(raw) ? .unverifiable : .none']:
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
        # Caption contracts keep their existing semantics (no dish anchor), and a
        # parenthesis cannot hide an unmeasured item inside a measured caption part:
        # caption tails run through the same prep-word whitelist.
        self.assertIn('guard let quantity = part.range(of: #"^\\d+(?:[./]\\d+)?\\s+"#', s)
        self.assertIn('tails(in: String(part[quantity.upperBound...])).allSatisfy(isPrepOnly)', s)
        self.assertIn('return Contract(text: source, ingredients: ingredients, method: method, dishes: [])', s)
        self.assertIn('return Contract(text: text, ingredients: ingredients, method: method, dishes: dishes)', s)

    def test_backend_binds_link_and_pasted_sources_and_fails_closed(self):
        s = (ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for token in ['var structuredSource: SourceRecipeFidelity.Contract?',
                      'var unverifiableSource = false',
                      # One shared pre-model recognition step covers all three extraction inputs.
                      'SourceRecipeFidelity.extraction(request.text ?? "")',
                      'SourceRecipeFidelity.extraction(caption)',
                      'SourceRecipeFidelity.extraction(String(Self.htmlToText(html).prefix(3500)))',
                      'fidelity = structuredSource ?? SourceRecipeFidelity.structuredRecipe(page)',
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
