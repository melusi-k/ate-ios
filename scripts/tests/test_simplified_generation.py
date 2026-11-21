from recipe_streaming_delta import restore as pre_streaming
"""Current simplified-path checks alongside exact historical inverses. Not Swift/UI proof."""
from pathlib import Path
import unittest,re,json,hashlib
ROOT=Path(__file__).resolve().parents[2]

class SimplifiedGenerationPreflight(unittest.TestCase):
    def test_actual_paths_are_single_pass_without_repair_examples_or_tools(self):
        backend=pre_streaming('Ate/Services/OnDeviceBackend.swift',(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text())
        self.assertNotIn('GenerationCancellation.optionalRepair',backend)
        self.assertNotIn('RecipePrompt.retryInstruction',backend)
        source=backend.split('    private func importSource(',1)[1].split('    @MainActor',1)[0]
        creative=backend.split('    func suggestRecipe(',1)[1].split('    private func parseRecipeResult',1)[0]
        for section in [source,creative]:
            for bad in ['RegionalDishTool','exampleMogodu','RecipeQuality.shortfall','Self.generate(', 'for attempt', 'repeat {']:
                self.assertNotIn(bad,section)
        self.assertEqual(source.count('selectSourceLines(text)'),1)
        self.assertEqual(creative.count('createSuggestion(generation.prompt)'),1)
        self.assertIn('try GenerationCancellation.check(error)',source)
        self.assertIn('SourceDraftImport.selection(text)',source)
        self.assertIn('generating: GenSuggestion.self',creative)
        selection=backend.split('    static func extractSourceLines(',1)[1].split('    static var isModelAvailable',1)[0]
        self.assertEqual(selection.count('session.respond('),1)
        self.assertIn('generating: GenSourceLines.self',selection)
        self.assertNotIn('GenRecipe',selection)

    def test_unknown_fields_and_all_source_lines_are_preserved_without_a_global_bypass(self):
        model=(ROOT/'Ate/Models/Models.swift').read_text()
        for field in ['var sourceDraft: SourceDraft?', 'var suggestionDraft: Bool?', 'source == .appleIntelligence && suggestionDraft == true']:
            self.assertIn(field,model)
        source=(ROOT/'Ate/Logic/SourceDraftImport.swift').read_text()
        for token in ['case .verified(let contract)', 'let unassigned = rows.indices.filter',
                      '(methods + unassigned).sorted()', 'quantity: 0', 'timeSeconds: nil', 'text: text',
                      '[.imported, .jsonLD].contains(card.source)']:
            self.assertIn(token,source)
        duration=(ROOT/'Ate/Logic/Durations.swift').read_text()
        self.assertIn('if card.isEditableDraft { return (card, false) }',duration)
        logic=(ROOT/'Ate/Logic/RecipeLogic.swift').read_text()
        self.assertIn('if c.isEditableDraft {',logic)
        self.assertIn('c.servings = max(0, c.servings)',logic)
        self.assertIn('else { c.servings = max(1, c.servings) }',logic)
        editor=(ROOT/'Ate/Views/Components.swift').read_text()
        for token in ['TextField("Servings", text: sourceServings)', 'TextField("Minutes", text: sourceTime',
                      'TextField("Amount", text: sourceAmount', 'DisclosureGroup("Original source")']:
            self.assertIn(token,editor)

    def test_mode_switch_drops_stale_error_and_link_cannot_enter_prompt_confirmation(self):
        view=pre_streaming('Ate/Views/AddRecipeSheet.swift',(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text())
        picker=view.split('Picker("Source", selection:',1)[1].split('}.pickerStyle',1)[0]
        for token in ['invalidateGeneration()', 'error = nil', 'socialError = nil', 'dishQuestion = nil',
                      'confirmedDish = nil', 'pendingDishCard = nil', 'mode = next']:
            self.assertIn(token,picker)
        self.assertIn('case _ where mode == .prompt && dishQuestion != nil',view)
        self.assertNotIn('case _ where mode != .image && dishQuestion != nil',view)
        self.assertIn('case .link:\n            guard !link',view)
        self.assertIn('req = ParseRequest(mode: .url, text: link)',view)

    def test_explore_one_message_soft_warnings_and_hard_safety_and_deadline(self):
        source=pre_streaming('Ate/Logic/RecipeDiscovery.swift',(ROOT/'Ate/Logic/RecipeDiscovery.swift').read_text())
        self.assertIn('message = error.localizedDescription',source)
        self.assertNotIn('message = "Couldn\'t create a suggestion.',source)
        self.assertIn('timeoutNanoseconds: UInt64 = 60_000_000_000',source)
        self.assertIn('cancel() // revoke the publication token',source)
        self.assertIn('recordLocal(.generationTimedOut)',source)
        self.assertNotIn('guard !RecipeQuality.needsInput(card)',source)
        for token in ['result.source == .appleIntelligence', 'RecipeQuality.isNonFoodTitle(card)',
                      'card.ingredients.filter',
                      'current.owner == input.owner', 'current.owner == owner', '!savedIDs.contains(card.id)']:
            self.assertIn(token,source)
        self.assertGreaterEqual(source.count('RecipeDiscovery.excludes(card, context: current'),2)
        view=pre_streaming('Ate/Views/SuggestedNewRecipesView.swift',(ROOT/'Ate/Views/SuggestedNewRecipesView.swift').read_text())
        self.assertIn('RecipeEditor(recipe: Binding',view)
        self.assertIn('save(review ?? card)',view)
        ui=(ROOT/'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        for token in ['XCTAssertTrue(retry.isEnabled)', 'XCTAssertEqual(retry.label, "Try again")',
                      'app.progressIndicators["discovery.loading"]']:
            self.assertIn(token,ui)

    def test_every_required_native_case_is_present_and_fixture_bytes_are_fixed(self):
        manifest=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        for cls in ['VerifiedPasteImportTests','CaptionPasteRecognitionTests','RecipeDiscoveryTests','RecipeDiscoveryIntentTests']:
            source=(ROOT/('AteTests/'+cls+'.swift')).read_text()
            for name in re.findall(r'    func (test\w+)\(',source):self.assertIn(cls+'/'+name,manifest)
        fixture=(ROOT/'AteTests/VerifiedPasteFixture.swift').read_text()
        for name,size in [('trifle',4074),('pasta',690)]:
            value=json.loads(re.search(r'    static let '+name+r' = (".*")$',fixture,re.M).group(1))
            self.assertEqual(len(value.encode()),size)
        raw=json.loads(re.search(r'    static let trifle = (".*")$',fixture,re.M).group(1))
        self.assertEqual(hashlib.sha256(raw.encode()).hexdigest(),'d127a6184d6fb9cd232e86f6798bd7362723f089b7a6b309611d0584db719490')
