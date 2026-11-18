"""Source guards for the #537 rework: chrome-copy, contrast, clearance and
duplicate-ingredient display only. The floating Cook footer design (main 99ea1045)
is retained; the branch's sibling/opaque-footer restructure is intentionally absent.
Native screenshot inspection still owns pixel acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class RecipeSheetChromeTests(unittest.TestCase):
    def test_sheet_state_is_accessibility_only_not_visible_debug_style_copy(self):
        source = (ROOT / 'Ate/Views/ExpandableRecipeDetailSheet.swift').read_text()
        self.assertNotIn('Text(isCompact ? "Recipe preview" : "Recipe details")', source)
        self.assertIn('.accessibilityLabel(isCompact ? "Recipe preview" : "Recipe details")', source)
        for identifier in ['recipeSheet.close', 'recipeSheet.collapse', 'recipeSheet.expandFully', 'expandRecipeDetails', 'recipeQuickLook']:
            self.assertIn(identifier, source)
        self.assertIn('.accessibilityElement(children: .contain)', source)

    def test_cook_footer_remains_floating_overlay_not_sibling(self):
        source = (ROOT / 'Ate/Views/RecipeDetailView.swift').read_text()
        self.assertIn('.overlay(alignment: .bottom)', source)
        self.assertIn('.floatShadow()', source)
        self.assertIn('footerChromeReserve', source)
        self.assertIn('Do not paint or reserve a bottom band', source)
        # The branch's sibling-footer restructure must NOT be present.
        self.assertNotIn('VStack(spacing: 0) {\n                    ScrollView {', source)
        self.assertNotIn('.contentShape(Rectangle())\n                    .clipped()', source)

    def test_rust_filled_controls_share_explicit_on_accent_theme_style(self):
        cook = (ROOT / 'Ate/Views/CookModeView.swift').read_text()
        self.assertNotIn('.borderedProminent', cook)
        for identifier in ['cookNextStep', 'cookFinish']:
            self.assertIn(identifier, cook)
        self.assertEqual(cook.count('.buttonStyle(.ate(.primary, height: 48))'), 2)
        style = (ROOT / 'Ate/Design/Theme.swift').read_text()
        self.assertIn('case .primary: return (Theme.primary, Theme.primaryForeground)', style)
        self.assertIn('.foregroundStyle(fg)', style)
        for filename in ['CookReflectionOfferSheet.swift', 'BetaTestingView.swift']:
            self.assertNotIn('.borderedProminent', (ROOT / 'Ate/Views' / filename).read_text())

    def test_duplicate_ingredient_display_is_presentation_only(self):
        logic = (ROOT / 'Ate/Logic/IngredientPresentation.swift').read_text()
        self.assertIn('static func rows(', logic)
        self.assertIn('static func uniqueNames(', logic)
        card = (ROOT / 'Ate/Views/Components.swift').read_text()
        self.assertIn('IngredientPresentation.rows(r.ingredients, units: units)', card)
        nutrition = (ROOT / 'Ate/Views/RecipeNutritionView.swift').read_text()
        self.assertEqual(nutrition.count('IngredientPresentation.uniqueNames('), 2)

    def test_first_ingredient_clearance_capture_present(self):
        tests = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        self.assertIn('recipe-sheet-full-first-ingredient-clear-of-cook-normal', tests)
        self.assertIn('First ingredient must scroll clear of Cook mode', tests)
        self.assertTrue((ROOT / 'AteUITests/RecipeDetailVisibility.swift').is_file())

if __name__ == '__main__':
    unittest.main()
