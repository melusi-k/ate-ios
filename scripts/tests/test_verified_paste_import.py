from steps_only_fixture_delta import restore as pre_fixture_correction
from recipe_streaming_delta import restore as pre_streaming
"""Source preservation and reachability checks, never native/UI qualification."""
from pathlib import Path
import unittest,json,hashlib,re
from verified_paste_import_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class VerifiedPasteImportPreflight(unittest.TestCase):
    def test_exact_inverse_and_missing_duplicate_unrelated_mutants(self):
        contracts=json.loads((ROOT/'scripts/tests/verified_paste_import_inverse.json').read_text())
        for path,c in contracts.items():
            s=pre_fixture_correction(path,pre_streaming(path,(ROOT/path).read_text()))
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
                    with self.assertRaises(AssertionError,msg=path):restore(path,changed)
    def test_paste_returns_before_availability_model_or_repair_and_explore_is_excluded(self):
        s=pre_streaming('Ate/Services/OnDeviceBackend.swift',(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text())
        route=s.split('    private func importSource(',1)[1].split('    @MainActor',1)[0]
        self.assertLess(route.index('VerifiedPasteImport.card('),route.index('if modelAvailable()'))
        self.assertEqual(route.count('selectSourceLines(text)'),1)
        for forbidden in ['Self.generate(', 'optionalRepair', 'exampleMogodu', 'RegionalDishTool', 'shortfall(']:self.assertNotIn(forbidden,route)
        self.assertIn('if !discovery, [.prompt, .url, .image].contains(request.mode)',s)
        self.assertEqual(s.count('VerifiedPasteImport.card('),1)
        self.assertEqual(pre_streaming('Ate/Views/AddRecipeSheet.swift',(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()).count('60_000_000_000'),1)
    def test_exact_owner_fixture_native_lifecycle_and_required_cases(self):
        s=(ROOT/'AteTests/VerifiedPasteFixture.swift').read_text()
        self.assertIn('190°C',s); self.assertIn('40-60 Minutes',s); self.assertIn('custardand',s)
        tests=(ROOT/'AteTests/VerifiedPasteImportTests.swift').read_text()
        manifest=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        names=re.findall(r'    func (test\w+)\(',tests)
        self.assertEqual(len(names),7)
        for name in names:self.assertIn('VerifiedPasteImportTests/'+name,manifest)
        for token in ['AddPromptSourceImport.parse','OnDeviceBackend(fallback: spy','XCTAssertEqual(spy.calls, 0)',
                      'source.add(RecipeLogic.normalize(card)','diskReload.exportJSON()', 'destination.importJSON(data)', 'ImageRenderer(content: RecipeCardView',
                      'RecipeLogic.normalize(RecipeLogic.normalize(card))', 'attempt.invalidate()',
                      'XCTAssertFalse(attempt.publish(token)', 'XCTAssertEqual(card.steps.count, 27)',
                      'XCTAssertEqual(card.ingredients.count, 28)']:
            self.assertIn(token,tests)
    def test_snapshot_is_optional_scoped_and_invalidated_after_edits(self):
        model=(ROOT/'Ate/Models/Models.swift').read_text()
        self.assertIn('var pastedSource: PastedRecipeSource?',model)
        self.assertIn('decodeIfPresent(PastedRecipeSource.self',model)
        logic=(ROOT/'Ate/Logic/RecipeLogic.swift').read_text()
        self.assertIn('if !keepsPaste { c.pastedSource = nil }',logic)
        duration=(ROOT/'Ate/Logic/Durations.swift').read_text()
        self.assertIn('if card.pastedSource?.matches(card) == true { return (card, false) }',duration)
        parser=(ROOT/'Ate/Logic/VerifiedPasteImport.swift').read_text()
        for token in ['card.source == .imported','card.ingredients == ingredients','card.steps == steps',
                      'card.timeMinutes == nil','card.aiNote == importNote','parsed == expected',
                      'n == number + 1','contract.issues(card).isEmpty']:
            self.assertIn(token,parser)
