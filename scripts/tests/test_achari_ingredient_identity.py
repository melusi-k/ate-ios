from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class AchariIngredientIdentityContracts(unittest.TestCase):
    def test_normalization_and_checks_use_food_identity(self):
        logic = (ROOT / 'Ate/Logic/RecipeLogic.swift').read_text()
        self.assertIn('c.ingredients.map(IngredientFieldNormalization.normalizeGenerated)', logic)
        quality = (ROOT / 'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('card.ingredients.map(IngredientFieldNormalization.identity)', quality)
        self.assertIn('anchors(IngredientFieldNormalization.identity(ingredient))', quality)
        self.assertIn('"achari paste"', quality)
        helper = (ROOT / 'Ate/Logic/IngredientFieldNormalization.swift').read_text()
        self.assertIn('nameWords.isSubset(of: preparationWords)', helper)
        self.assertIn('IngredientParser.units[unit.lowercased()] == nil', helper)
        tests = (ROOT / 'AteTests/AchariIngredientIdentityTests.swift').read_text()
        for expected in ['1 onion diced', 'achari paste', 'mentions onion', 'Real missing paste must still gate Save', 'Normalization must be idempotent']:
            self.assertIn(expected, tests)
