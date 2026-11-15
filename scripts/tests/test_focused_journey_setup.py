"""Setup-only contracts. Native journey execution remains required."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class FocusedJourneySetupTests(unittest.TestCase):
    def test_fixture_is_debug_ui_testing_and_explicit_flag_only(self):
        source = (ROOT / 'Ate/App/FocusedJourneyQAFixtures.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG\n'))
        self.assertTrue(source.rstrip().endswith('#endif'))
        self.assertIn('guard AppConfig.isUITesting else { return }', source)
        self.assertIn('guard cook || reorder else { return }', source)
        for forbidden in ['store.cookSession', 'CookingHistory.', 'record(', '.layout.sort = .myOrder']:
            self.assertNotIn(forbidden, source)
        self.assertIn('store.layout = LibraryLayout()', source)
        self.assertIn('store.path = [.recipe(recipe.id)]', source)
        app = (ROOT / 'Ate/App/AteApp.swift').read_text()
        block = app.split('let upgradeRuntime =', 1)[1].split('#else', 1)[0]
        self.assertIn('FocusedJourneyQAFixtures.prepare(st)', block)

    def test_asserted_behaviour_remains_real(self):
        source = (ROOT / 'AteUITests/AteUITests.swift').read_text()
        cook = source.split('func testCookModeExitDoesNotRecordCookingDay()', 1)[1].split('func testCookModeCompletionRecordsCookingDay()', 1)[0]
        for expected in ['-qaSavedRecipeForCookExit', 'app.buttons["Cook mode"].tap()', 'app.buttons["Exit"].tap()',
                         'tabFromRecipeDetail("Journal"', 'hub.tap()', 'todayWithoutCooking.label.contains("no cooking recorded")']:
            self.assertIn(expected, cook)
        reorder = source.split('func test29_ReorderMyOrder()', 1)[1].split('func testFirstLibraryRecipeActions', 1)[0]
        for expected in ['-qaSavedRecipesForReorder', 'pick("sortMenu", "My order")', 'first.press(forDuration: 1.2)',
                         'app.buttons["Move up"].tap()', 'XCTAssertLessThan(second.frame.minY, first.frame.minY',
                         'XCTAssertLessThan(text("First dish").frame.minY, text("Second dish").frame.minY',
                         'thenDragTo: text("Second dish")']:
            self.assertIn(expected, reorder)
        self.assertNotIn('addNamed(', reorder)
        self.assertNotIn('addPromptRecipe()', cook)
