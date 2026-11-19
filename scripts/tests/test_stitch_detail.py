"""Native detail presentation guards, not Swift/visual evidence."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from stitch_detail_delta import restore
ROOT = Path(__file__).resolve().parents[2]

class StitchDetailSourceTests(unittest.TestCase):
    def test_exact_inverse_preserves_all_parent_bytes_and_rejects_mutations(self):
        contracts = json.loads((ROOT / 'scripts/tests/stitch_detail_inverse.json').read_text())
        for path, contract in contracts.items():
            raw = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(restore('main:' + path, raw).encode()).hexdigest(), contract['parent_sha'])
            for fragment in contract['fragments']:
                for changed in [raw.replace(fragment['slice'], '', 1), raw + fragment['slice']]:
                    with self.assertRaises(AssertionError): restore('main:' + path, changed)
    def test_metadata_is_read_only_and_does_not_invent_time_or_provenance(self):
        logic = (ROOT / 'Ate/Logic/RecipeDetailMetadata.swift').read_text()
        for token in ['multipliedReportingOverflow', '[1.0, 2.0, 3.0].contains(factor)', 'recipe.timeMinutes.flatMap', 'return configured ?? true', 'if isUITesting && arguments.contains("-qaStitchRecipeDetailOff")']:
            self.assertIn(token, logic)
        for token in ['store.update', 'UserDefaults', 'Harmony', 'variant', 'substitut', 'parseRecipe']:
            self.assertNotIn(token, logic)
    def test_current_actions_footer_and_native_detents_remain(self):
        source = (ROOT / 'Ate/Views/RecipeDetailView.swift').read_text()
        for token in ['store.beginCookSession(recipeID: recipeID, factor: factor)', 'store.addToShopping(recipe, factor: factor)', 'CookPlanSheet(recipeID: recipeID)', 'footerChromeReserve', 'RecipeNutritionView', 'askCard(recipe)', 'detailHierarchy: stitchDetail']:
            self.assertIn(token, source)
        # Original action/save/share semantics are carried as exact parent fragments
        # by full-file inverse; this asserts the new display is not presented as a variant.
        self.assertNotIn('Harmony', source)
        self.assertNotIn('Create variant', source)
        component = (ROOT / 'Ate/Views/Components.swift').read_text()
        self.assertIn('var detailHierarchy = false', component)
        self.assertIn('if detailHierarchy {', component)
        self.assertIn('recipe.steps.heading', component)
    def test_all_new_native_methods_have_explicit_route(self):
        ui = (ROOT / 'AteUITests/StitchRecipeDetailUITests.swift').read_text()
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/StitchRecipeDetailUITests', workflow)
        for method in re.findall(r'    func (test\w+)\(', ui): self.assertIn(method, workflow)
        required = (ROOT / 'scripts/full-unit-required.txt').read_text()
        for method in re.findall(r'    func (test\w+)\(', (ROOT / 'AteTests/RecipeDetailMetadataTests.swift').read_text()):
            self.assertIn('RecipeDetailMetadataTests/' + method, required)
