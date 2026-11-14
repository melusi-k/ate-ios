from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class BoundedSheetFoldIn(unittest.TestCase):
    def test_all_three_selected_and_named_passes_required(self):
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        for cls, name in [('CoverageUITests', 'test32c_ExpandableRecipeSheetOpensExpandsAndDismisses'),
                          ('CoverageUITests', 'test32d_ExpandableRecipeSheetLandscapeRotationAndDismissal'),
                          ('LibraryProteinGroupingUITests', 'testPorkLedRibsAppearUnderPorkAtNormalText')]:
            self.assertIn('-only-testing:AteUITests/' + cls + '/' + name, source)
            self.assertIn(cls + ' ' + name + "]' passed", source)
        self.assertIn('library-protein-sheet-attachments', source)
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', source)
    def test_fixture_and_visibility_are_narrow(self):
        fixture = (ROOT / 'Ate/App/RecipeSheetQAFixtures.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('guard AppConfig.isUITesting,', fixture)
        self.assertIn('contains("-qaSavedRecipeForSheet")', fixture)
        for forbidden in ['store.path', 'detent =', 'scrollTo', 'factor =']:
            self.assertNotIn(forbidden, fixture)
        tests = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        self.assertIn('for _ in 0..<5 where !RecipeDetailVisibility.contains(firstIngredient', tests)
        helper = (ROOT / 'AteUITests/RecipeDetailVisibility.swift').read_text()
        self.assertIn('band.contains(frame) && row.isHittable', helper)
        self.assertIn('footer.frame.minY - 8', helper)
        self.assertIn('.accessibilityIdentifier("recipe.ingredient.\\(index)")', (ROOT / 'Ate/Views/Components.swift').read_text())
