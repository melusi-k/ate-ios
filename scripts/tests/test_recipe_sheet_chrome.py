"""Source guards; native screenshot inspection still owns pixel acceptance."""
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

    def test_actual_scroll_owns_opaque_footer_and_keeps_measured_timer_reserve(self):
        source = (ROOT / 'Ate/Views/RecipeDetailView.swift').read_text()
        scroll = source.split('.accessibilityIdentifier("recipe.detail.scroll")', 1)[1].split('RecipeNotFoundView', 1)[0]
        self.assertIn('.safeAreaInset(edge: .bottom, spacing: 0)', scroll)
        self.assertIn('.background(Theme.background.ignoresSafeArea(edges: .bottom))', scroll)
        self.assertIn('.padding(.bottom, footerChromeReserve)', scroll)
        self.assertEqual(source.count('.safeAreaInset(edge: .bottom'), 1)

    def test_existing_selected_journey_checks_first_and_last_content_and_all_detents(self):
        tests = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        journey = tests.split('func test32c_ExpandableRecipeSheetOpensExpandsAndDismisses()', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('UICTContentSizeCategoryL', journey)
        self.assertIn('firstIngredient.frame.intersects(cookFooter.frame)', journey)
        self.assertIn('lastField.frame.maxY, cookFooter.frame.minY - 1', journey)
        self.assertIn('recipe-sheet-medium-no-visible-state-label-normal', journey)
        self.assertIn('recipe-sheet-full-first-ingredient-clear-of-cook-normal', journey)
        self.assertIn('recipe-sheet-full-bottom-content-clear-of-cook-normal', journey)
        self.assertIn('servings.buttons["2×"].isSelected', journey)
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/CoverageUITests/test32c_ExpandableRecipeSheetOpensExpandsAndDismisses', workflow)

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
