from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class GeneratedTitleReviewContracts(unittest.TestCase):
    def test_review_hint_is_generated_only_and_not_quality_or_repair_gate(self):
        helper=(ROOT/'Ate/Logic/GeneratedTitleReview.swift').read_text()
        self.assertIn('guard RecipeQuality.isGenerated(card)',helper)
        self.assertIn('[("wing", "rib"), ("rib", "wing")]',helper)
        for phrase in ['!title.contains(written)','!ingredients.contains(named)','!method.contains(named)','nothing has been renamed']:
            self.assertIn(phrase,helper)
        for file in ['Ate/Logic/RecipeQuality.swift','Ate/Logic/RecipeDraftRepair.swift']:
            self.assertNotIn('GeneratedTitleReview',(ROOT/file).read_text())
        ui=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('GeneratedTitleReview.warning(d)',ui)
        self.assertIn('.accessibilityIdentifier("generatedTitleReview")',ui)
