from approved_merge_537 import normalize
"""Source guards; native screenshot inspection still owns pixel acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class RecipeSheetChromeTests(unittest.TestCase):
    def test_sheet_state_is_accessibility_only_not_visible_debug_style_copy(self):
        source = normalize('source:Ate/Views/ExpandableRecipeDetailSheet.swift', (ROOT / 'Ate/Views/ExpandableRecipeDetailSheet.swift').read_text())
        self.assertNotIn('Text(isCompact ? "Recipe preview" : "Recipe details")', source)
        self.assertIn('.accessibilityLabel(isCompact ? "Recipe preview" : "Recipe details")', source)
        for identifier in ['recipeSheet.close', 'recipeSheet.collapse', 'recipeSheet.expandFully', 'expandRecipeDetails', 'recipeQuickLook']:
            self.assertIn(identifier, source)
        self.assertIn('.accessibilityElement(children: .contain)', source)

    def test_footer_is_outside_clipped_scroll_and_keeps_measured_timer_reserve(self):
        source = normalize('source:Ate/Views/RecipeDetailView.swift', (ROOT / 'Ate/Views/RecipeDetailView.swift').read_text())
        scroll = source.split('.accessibilityIdentifier("recipe.detail.scroll")', 1)[1].split('RecipeNotFoundView', 1)[0]
        self.assertIn('VStack(spacing: 0) {\n                    ScrollView {', source)
        self.assertIn('.contentShape(Rectangle())', scroll)
        self.assertIn('.clipped()', scroll)
        self.assertLess(scroll.index('.clipped()'), scroll.index('Button {'))
        self.assertIn('.background(Theme.background.ignoresSafeArea(edges: .bottom))', scroll)
        self.assertIn('.padding(.bottom, footerChromeReserve)', scroll)
        self.assertNotIn('.safeAreaInset(edge: .bottom', source)

    def test_existing_selected_journey_checks_first_and_last_content_and_all_detents(self):
        tests = normalize('source:AteUITests/CoverageUITests.swift', (ROOT / 'AteUITests/CoverageUITests.swift').read_text())
        journey = tests.split('func test32c_ExpandableRecipeSheetOpensExpandsAndDismisses()', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('UICTContentSizeCategoryL', journey)
        self.assertIn('firstIngredient.frame.intersects(cookFooter.frame)', journey)
        self.assertIn('lastField.frame.maxY, cookFooter.frame.minY - 1', journey)
        self.assertIn('recipe-sheet-medium-no-visible-state-label-normal', journey)
        self.assertIn('recipe-sheet-full-first-ingredient-clear-of-cook-normal', journey)
        self.assertIn('recipe-sheet-full-bottom-content-clear-of-cook-normal', journey)
        self.assertIn('servings.buttons["2×"].isSelected', journey)
        workflow = normalize('source:.github/workflows/compile-check.yml', (ROOT / '.github/workflows/compile-check.yml').read_text())
        self.assertIn('-only-testing:AteUITests/CoverageUITests/test32c_ExpandableRecipeSheetOpensExpandsAndDismisses', workflow)

    def test_rust_filled_controls_share_explicit_on_accent_theme_style(self):
        cook = normalize('source:Ate/Views/CookModeView.swift', (ROOT / 'Ate/Views/CookModeView.swift').read_text())
        self.assertNotIn('.borderedProminent', cook)
        for identifier in ['cookNextStep', 'cookFinish']:
            self.assertIn(identifier, cook)
        self.assertEqual(cook.count('.buttonStyle(.ate(.primary, height: 48))'), 2)
        style = normalize('source:Ate/Design/Theme.swift', (ROOT / 'Ate/Design/Theme.swift').read_text())
        self.assertIn('case .primary: return (Theme.primary, Theme.primaryForeground)', style)
        self.assertIn('.foregroundStyle(fg)', style)
        for filename in ['CookReflectionOfferSheet.swift', 'BetaTestingView.swift']:
            self.assertNotIn('.borderedProminent', (ROOT / 'Ate/Views' / filename).read_text())

    def test_entire_ui_file_reconstructs_original_except_last_field_reveal(self):
        import hashlib
        source=normalize('source:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_text())
        source=source.replace('        // Medium detent prioritizes native sheet resizing over downward content\n        // scrolling. Expand once before returning through the retained detail.\n        shot("recipe-sheet-reexpanded-medium-before-return-to-servings")\n        fully.tap()\n        RecipeDetailVisibility.reveal(servings, scroll: detailScroll, header: header, footer: cookFooter)\n        shot("recipe-sheet-reexpanded-full-after-return-to-servings")', '        for _ in 0..<5 where !servings.isHittable { detailScroll.swipeDown() }')
        replacement = """        // Partial hittability is not full clearance. Keep the existing five-gesture
        // budget and require the same visible band used for the first ingredient.
        RecipeDetailVisibility.reveal(lastField, scroll: detailScroll, header: header, footer: cookFooter)"""
        self.assertEqual(source.count(replacement), 1)
        source=source.replace(replacement, "        for _ in 0..<5 where !lastField.isHittable { detailScroll.swipeUp() }").encode()
        self.assertEqual(hashlib.sha256(source).hexdigest(),'9426f1c479e994f769ade1f69ac0a55ee092532bc04d2bb1e70c639faf31525c')
