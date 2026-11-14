from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class BoundedRecipeSheet(unittest.TestCase):
    def test_both_real_journeys_are_required_in_lane(self):
        tests = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        portrait = tests.split('func test32c_ExpandableRecipeSheetOpensExpandsAndDismisses()',1)[1].split('\n    func ',1)[0]
        landscape = tests.split('func test32d_ExpandableRecipeSheetLandscapeRotationAndDismissal()',1)[1].split('\n    func ',1)[0]
        self.assertNotIn('addPrompt(', portrait)
        self.assertNotIn('landscapeLeft', portrait)
        for token in ['landscapeLeft', 'gridCard', 'Compact-height expansion', 'sidebar.Library', 'sidebar.Shopping list', 'A dismissed sheet must not reappear']:
            self.assertIn(token, landscape)
        for test in [portrait, landscape]:
            self.assertIn('-qaSavedRecipeForSheet', test)
            self.assertIn('UICTContentSizeCategoryL', test)
            self.assertIn('defer { XCUIDevice.shared.orientation = .portrait }', test)
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        for name in ['test32c_ExpandableRecipeSheetOpensExpandsAndDismisses', 'test32d_ExpandableRecipeSheetLandscapeRotationAndDismissal']:
            self.assertIn('-only-testing:AteUITests/CoverageUITests/' + name, workflow)
            self.assertIn(name + "]' passed", workflow)
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', workflow)

    def test_ingredient_capture_requires_full_visible_band_not_intersection_alone(self):
        helper = (ROOT / 'AteUITests/RecipeDetailVisibility.swift').read_text()
        for token in ['max(viewport.minY, header.frame.maxY) + 8', 'min(viewport.maxY, footer.frame.minY - 8)',
                      'frame.width > 0 && frame.height > 0 && band.contains(frame) && row.isHittable']:
            self.assertIn(token, helper)
        for file, row in [('CoverageUITests.swift', 'firstIngredient'), ('IngredientDisplayUITests.swift', 'row')]:
            source = (ROOT / 'AteUITests' / file).read_text()
            self.assertIn('RecipeDetailVisibility.reveal(' + row, source)
            self.assertIn('XCTAssertTrue(RecipeDetailVisibility.contains(' + row, source)
        duplicate = (ROOT / 'AteUITests/IngredientDisplayUITests.swift').read_text()
        for token in ['XCTAssertEqual(rows.count, 1', 'row.label.contains("for serving")', 'row.label.lowercased().contains("sliced")']:
            self.assertIn(token, duplicate)

    def test_seed_has_no_asserted_sheet_state_or_hidden_content(self):
        source = (ROOT / 'Ate/App/RecipeSheetQAFixtures.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('guard AppConfig.isUITesting,', source)
        self.assertIn('contains("-qaSavedRecipeForSheet")', source)
        for forbidden in ['store.path', 'store.quickLook', 'detent =', 'scrollTo', 'factor =']:
            self.assertNotIn(forbidden, source)
        for food in ['salmon fillets', 'white miso', 'honey', 'garlic', 'rice']:
            self.assertIn(food, source)
