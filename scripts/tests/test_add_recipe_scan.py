"""Presentation/source checks, not native or OCR quality evidence."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from add_recipe_scan_delta import restore
ROOT = Path(__file__).resolve().parents[2]

class AddRecipeScanSourceTests(unittest.TestCase):
    def test_exact_parent_inverse_and_mutations_fail_closed(self):
        contracts = json.loads((ROOT / 'scripts/tests/add_recipe_scan_inverse.json').read_text())
        for path, contract in contracts.items():
            raw = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(restore('main:' + path, raw).encode()).hexdigest(), contract['parent_sha'])
            self.assertIsInstance(restore('main:' + path, raw.encode()), bytes)
            for fragment in contract['fragments']:
                new = fragment['slice']
                for invalid in [raw.replace(new, '', 1), raw + new]:
                    with self.assertRaises(AssertionError):
                        restore('main:' + path, invalid)
        self.assertEqual(restore('other', 'untouched'), 'untouched')
    def test_generation_repair_input_persistence_and_source_contracts_unchanged(self):
        source = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        suffix = source[source.index('    @ViewBuilder private func coverEditor('):]
        self.assertEqual(hashlib.sha256(suffix.encode()).hexdigest(), '63a53effca43023d7d239b1921714f6ff43b7454764e2830c80c7c817f5b21dd')
        for token in ['RecipeQuality.needsInput(d)', 'RecipeQuality.shortfall(d)', 'confirmDraft', 'repairDraftQuality', 'invalidateInputLoads()', 'onSave(RecipeLogic.normalize(d))']:
            self.assertIn(token, source)
    def test_new_header_uses_draft_values_and_off_keeps_original_copy(self):
        source = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        for token in ['if scanPresentation, let d = draft { scanReviewHeader(d) }', 'if !scanPresentation, let d = draft, let conf = d.aiConfidence', 'Counts describe this draft, not extraction accuracy.', 'Label("Add a recipe",', 'draft servings', 'Total time not given']:
            self.assertIn(token, source)
        self.assertNotIn('94%', source)
        self.assertNotIn('Scan Another Page', source)
        summary = (ROOT / 'Ate/Logic/AddRecipeReviewSummary.swift').read_text()
        for token in ['recipe.ingredients.count', 'recipe.steps.count', 'recipe.servings > 0', 'recipe.timeMinutes.flatMap', 'return configured ?? true', 'if isUITesting && arguments.contains("-qaStitchAddRecipeScanOff")']:
            self.assertIn(token, summary)
        for token in ['aiConfidence', 'UserDefaults', 'AppStore', 'parseRecipe', 'OCR']:
            self.assertNotIn(token, summary.split('struct AddRecipeReviewSummary:', 1)[1].split('enum AddRecipeScanFeature', 1)[0])
    def test_native_names_selected_and_required_unit_union_extended(self):
        ui = (ROOT / 'AteUITests/AddRecipeScanUITests.swift').read_text()
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/AddRecipeScanUITests', workflow)
        for name in re.findall(r'    func (test\w+)\(', ui):
            self.assertIn(name, workflow)
        units = (ROOT / 'AteTests/AddRecipeReviewSummaryTests.swift').read_text()
        required = (ROOT / 'scripts/full-unit-required.txt').read_text()
        for name in re.findall(r'    func (test\w+)\(', units):
            self.assertIn('AddRecipeReviewSummaryTests/' + name, required)
