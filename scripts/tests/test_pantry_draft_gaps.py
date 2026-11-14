from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PantryDraftGapTests(unittest.TestCase):
    def test_exemption_is_only_plain_pantry_and_does_not_drop_real_ingredient_checks(self):
        quality = (ROOT / 'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('if name == "salt" || name == "oil" { return true }', quality)
        self.assertIn('guard name == "pepper" else { return false }', quality)
        self.assertIn('prep.isDisjoint', quality)
        self.assertIn('"sliced"', quality)
        self.assertIn('"to taste"', quality)
        self.assertIn('where !isPlainPantrySeasoning(ingredient)', quality)
        self.assertIn('ingredientAnchors.isDisjoint(with: allStepWords)', quality)
        self.assertIn('allStepWords.intersection(foods).subtracting(listed)', quality)

    def test_visible_and_explicit_repair_gap_contract_has_no_hidden_step_count(self):
        quality = (ROOT / 'Ate/Logic/RecipeQuality.swift').read_text()
        shortfall = quality.split('static func shortfall(', 1)[1].split('/// One plated', 1)[0]
        self.assertIn('var out = issues(c)', shortfall)
        self.assertNotIn('minSteps', quality)
        self.assertNotIn('Needs at least', shortfall)
        ui = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('ForEach(RecipeQuality.issues(d)', ui)
        repair = (ROOT / 'Ate/Logic/RecipeDraftRepair.swift').read_text()
        self.assertIn('newGaps.isStrictSubset(of: oldGaps)', repair)
        self.assertIn('newGaps.subtracting(oldGaps)', repair)
        self.assertIn('added a new problem', repair)
        self.assertIn('did not fix any of the listed gaps', repair)

    def test_exact_device_fixture_and_substantive_repair_regressions_exist(self):
        native = (ROOT / 'AteTests/PantryDraftGapTests.swift').read_text()
        for term in ['Sticky pork wings', 'pork ribs', 'barbecue sauce', '135 * 60',
                     'Prep: 10 min', 'normalized.timeMinutes, 150',
                     'lemon pepper', 'chilli oil', 'salted butter',
                     'RecipeDraftRepair.accept', 'RecipeDraftRepair.automaticImproves']:
            self.assertIn(term, native)

    def test_meat_amount_advice_is_guidance_only_not_a_new_gate(self):
        backend = (ROOT / 'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertIn('explicit piece count (pcs) or weight (g/kg)', backend)
        self.assertIn('Preserve any supplied source count or weight; do not invent one.', backend)
        quality = (ROOT / 'Ate/Logic/RecipeQuality.swift').read_text()
        self.assertNotIn('1 wings', quality)
        native = (ROOT / 'AteTests/PantryDraftGapTests.swift').read_text()
        self.assertIn('testUsedAndUnusedSlicedPepperRemainVegetablesNotPantrySeasoning', native)
