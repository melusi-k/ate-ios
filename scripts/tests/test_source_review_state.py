"""Source/inverse guards, not native device or Swift qualification."""
from pathlib import Path
import hashlib,json,unittest
from source_review_state_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class SourceReviewStateTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_unrelated_mutants(self):
  for path,c in json.loads((ROOT/'scripts/tests/source_review_state_inverse.json').read_text()).items():
   s=(ROOT/path).read_text()
   self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
   for f in c['fragments']:
    for mutant in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
     if mutant==restore(path,s):continue
     with self.assertRaises(AssertionError):restore(path,mutant)
 def test_source_count_scope_does_not_parse_quantities_or_change_generated_rules(self):
  s=(ROOT/'Ate/Logic/RecipeQuality.swift').read_text()
  self.assertIn('isMainDish(c) && !SourceDraft.applies(to: c) && real.count < 4',s)
  self.assertIn('if !ingredient.quantity.isFinite || ingredient.quantity <= 0',s)
  c=json.loads((ROOT/'scripts/tests/source_review_state_inverse.json').read_text())['Ate/Logic/RecipeQuality.swift']
  self.assertEqual(len(c['fragments']),1)
  self.assertNotIn('IngredientParser',c['fragments'][0]['new'])
 def test_repair_action_and_backend_share_eligibility_without_widening_authority(self):
  logic=(ROOT/'Ate/Logic/RecipeDraftRepair.swift').read_text()
  self.assertIn('RecipeQuality.isGenerated(card) && !RecipeQuality.shortfall(card).isEmpty',logic)
  self.assertIn('guard canRepair(card) else {',logic)
  view=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
  section=view.split('if RecipeDraftRepair.canRepair(recipe) {',1)[1].split('\n                    }',1)[0]
  self.assertIn('Label("Repair these gaps"',section)
  self.assertIn('await rewrite(recipe, repairQuality: true)',section)
 def test_unknown_nutrition_stays_unavailable_and_clear_wording_is_used(self):
  s=(ROOT/'Ate/Logic/RecipeNutrition.swift').read_text()
  self.assertIn('recipe.servings == 0 && recipe.isEditableDraft',s)
  self.assertIn('Self.servingsAreUnspecified(recipe) ? "servings needed" : "invalid servings"',s)
  self.assertIn('perServing: nil, totalRecipe: nil, contributions: []',s)
  v=(ROOT/'Ate/Views/RecipeNutritionView.swift').read_text()
  self.assertIn('Add the number of servings to estimate nutrition. Ate won\'t guess it.',v)
  self.assertIn('!result.incompleteIngredients.isEmpty && !RecipeNutritionCalculator.servingsAreUnspecified(recipe)',v)
