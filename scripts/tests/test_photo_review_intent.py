from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PhotoReviewIntentContracts(unittest.TestCase):
    def test_existing_save_gate_and_reconciliation_are_retained(self):
        s=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('!didEdit && !confirmedDraft',s)
        self.assertIn("It's right, let me save",s)
        q=(ROOT/'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('it is listed but never used in the steps.',q)
        self.assertIn('The method stops after browning.',q)
    def test_actual_card_renders_labels_and_safe_units(self):
        s=(ROOT/'Ate/Views/Components.swift').read_text()
        self.assertIn('GeneratedRecipeConsistency.timeLabels(r)',s)
        self.assertIn('IngredientFieldNormalization.displayUnit(ing, generated: RecipeQuality.isGenerated(r))',s)
        self.assertIn('ForEach(Array(r.steps.enumerated())',s)
        tests=(ROOT/'AteTests/PhotoReviewIntentTests.swift').read_text()
        for phrase in ['Total 17 min','Prep 12 min','Cook 5 min','never manufacture cooking instructions','Do not rename the named dish from pixels','Do not guess an ambiguous split']:
            self.assertIn(phrase,tests)
