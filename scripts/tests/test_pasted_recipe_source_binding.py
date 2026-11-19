"""Packet D r2/r3: pasted/caption/page source binding pins (text contracts, not model runs)."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PastedRecipeSourceBinding(unittest.TestCase):
    def test_prompt_and_social_never_clip_the_source(self):
        s = (ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        self.assertNotIn('text.prefix(500)', s)
        self.assertNotIn('caption.prefix(3000)', s)
        # Packet D r3: page() never clips either; the caller feeds the verified
        # contract's own text or a bounded head. (screenshot keeps its own cap.)
        page_fn = s.split('static func page(_ text: String) -> String {', 1)[1].split('\n    }', 1)[0]
        self.assertNotIn('prefix', page_fn)

    def test_extraction_order_fail_closed_and_recipe_shaped(self):
        s = (ROOT/'Ate/Logic/SourceRecipeFidelity.swift').read_text()
        self.assertIn('inlineCaption(raw) ?? structuredRecipe(raw) ?? multiPartRecipe(raw) ?? captionSections(raw)', s)
        self.assertIn('claimsCaptionSections(raw) || isRecipeShaped(raw) ? .unverifiable : .none', s)
        for token in ['static func isRecipeShaped(_ raw: String) -> Bool',
                      'static func multiPartRecipe(_ raw: String) -> Contract?',
                      'private static func multiPartCandidate(',
                      'static func captionSections(_ raw: String) -> Contract?',
                      'static func captionDishName(_ header: String) -> String?',
                      'static func applyingDishConfirmation(_ card: inout RecipeCard, contract: Contract, hint: String)',
                      'let pinchClass = parsed.quantity == 1',
                      r'#"^\d+\s+\d+/\d+"#',
                      'private static func isSectionHeading(_ line: String) -> Bool',
                      'private static func isShapedLine(_ line: String) -> Bool',
                      'private static func unmeasuredShapedItem(_ line: String) -> Ingredient?',
                      'if isSectionHeading(stripped) { continue }',
                      'lower.hasPrefix("for ") || lower.hasPrefix("to ")',
                      'faqs?|frequently asked|related recipes',
                      r'[ \t\x{00A0}\x{202F}]',
                      r'^a (?:pinch|handful|dash|splash) of ',
                      '(amount * 100).rounded() == (ingredient.quantity * 100).rounded()',
                      'without an amount; do not invent one.']:
            self.assertIn(token, s)

    def test_prompt_tab_gate_and_confirm_split(self):
        s = (ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        # Skip the question only when the bound source names the dish itself.
        self.assertIn('if case .verified(let contract) = SourceRecipeFidelity.extraction(prompt) { return !contract.dishes.isEmpty }', s)
        # The first BOUND import is kept and the answer only titles it, through the
        # contradiction guard; an unbound idea regenerates instead of being renamed.
        self.assertIn('@State private var pendingDishCard: RecipeCard?', s)
        self.assertIn('@State private var pendingDishContract: SourceRecipeFidelity.Contract?', s)
        self.assertIn('pendingDishCard = boundContract != nil ? normalized : nil', s)
        # The contract returned WITH this parse's own result; no shared handoff exists.
        self.assertIn('let parsed = try await store.backend.parseRecipeWithContract(req)', s)
        self.assertIn('boundContract = parsed.contract', s)
        self.assertIn('if var kept = pendingDishCard, let contract = pendingDishContract {', s)
        self.assertIn('SourceRecipeFidelity.applyingDishConfirmation(&kept, contract: contract, hint: name)', s)
        # The kept card never outlives its input.
        self.assertIn('.onChange(of: prompt) { _, _ in pendingDishCard = nil; pendingDishContract = nil }', s)
        self.assertIn('.onChange(of: link) { _, _ in pendingDishCard = nil; pendingDishContract = nil }', s)
        self.assertNotIn('req = ParseRequest(mode: .url, text: link, dishHint: name)', s)
        self.assertNotIn('Context: \\(ctx.prefix(400))', s)
        self.assertNotIn('text: ctx.isEmpty ? name : "\\(name). Context: \\(ctx)"', s)
        self.assertIn('req = ParseRequest(mode: .prompt, text: ctx.isEmpty ? name : ctx, dishHint: ctx.isEmpty ? nil : name)', s)

    def test_backend_wiring_and_fail_closed_gates(self):
        s = (ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for token in ['.count(1...60)) var ingredients: [GenIngredient]',
                      '.count(1...40)) var steps: [GenStep]',
                      '(request.text ?? "").count > 6000',
                      '(request.text ?? "").count > 1200',
                      'The cook confirmed the dish:',
                      'SourceRecipeFidelity.applyingDishConfirmation(&card, contract: contract, hint: hint)',
                      'if Self.isExampleEcho(card, sourceText: contextUser',
                      'static func isExampleEcho(_ card: RecipeCard, sourceText: String) -> Bool',
                      'captionCache[cacheKey]',
                      'Paste the caption text into Prompt instead.',
                      'var prompt: String',
                      'SourceRecipeFidelity.extraction(Self.htmlToText(html))',
                      '.prefix(20000)',
                      'let page = fidelity.map { String($0.text.prefix(6000)) } ?? String(pageText.prefix(6000))',
                      'func parseRecipeWithContract(_ request: ParseRequest) async throws -> (card: RecipeCard, contract: SourceRecipeFidelity.Contract?)',
                      'try await parseRecipeWithContract(request).card',
                      'return (normalized, fidelity)',
                      'case .none = SourceRecipeFidelity.extraction(request.text ?? ""),',
                      "throw SocialCaptionError(platform: platform, reason:"]:
            self.assertIn(token, s)
        self.assertNotIn('if fidelity == nil, Self.isExampleEcho', s)
        # Packet D r5: no shared static contract handoff may exist at all.
        self.assertNotIn('lastVerifiedContract', s)
        self.assertNotIn('publishVerifiedContract', s)
        self.assertNotIn('verifiedContract(forInput', s)
        self.assertNotIn('htmlToText(html).prefix(3500)', s)
        # Social gate: a glossary dish word alone no longer rescues generic copy.
        self.assertNotIn('''!CaptionAnalysis.hasRecipeSignals(caption),
               CuisineGlossary.matches(in: caption).isEmpty,''', s)

    def test_parse_request_carries_the_dish_hint(self):
        s = (ROOT/'Ate/Services/BackendService.swift').read_text()
        self.assertIn('var dishHint: String? = nil', s)

    def test_swift_contract_fixtures_exist(self):
        s = (ROOT/'AteTests/SourceRecipeFidelityTests.swift').read_text()
        for token in ['final class MultiPartPastedRecipeContracts',
                      'final class CaptionDishAndQuantityLessContracts',
                      'final class DishConfirmationContracts',
                      'final class ExampleEchoRejectionContracts',
                      'final class URLPageMultiPartContracts',
                      'final class RecipeShapedFailClosedContracts',
                      'testNBSPAndWhitespaceVariantsVerifyIdentically',
                      'testContradictingConfirmKeepsTheSourceAndSaysSo',
                      'testPageVerifiesWithAllComponents',
                      'testKnownDishWordDoesNotRescueRecipeShapedText',
                      'testASCIIFractionsAndMixedNumbersRoundTrip',
                      'final class PagePromptAndRegexContracts',
                      'testFinalPagePromptCarriesIngredientLinesPastTheOldCap',
                      'testCaptionHeadingsAreStructuralAndTitleCaseItemsAreRetained',
                      'testCaptionDishNameSplitsOnEnDashEmDashHyphenAndColon',
                      'final class RequestScopedContractContracts',
                      'testInterleavedParsesKeepTheirOwnInputsAndContracts',
                      'testClosingFoodNounNeverMakesAHeading',
                      'testMultiPartKeepsFoodNounItemsWithMethodPresent',
                      'testRegexPathsCompileAndMatch',
                      r'Marry Me Shrimp Pasta',
                      r'\u{1F517}']:
            self.assertIn(token, s)
        self.assertNotIn(r'\u{D83D}', s)

if __name__ == '__main__':
    unittest.main()
