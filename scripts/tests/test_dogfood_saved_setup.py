"""Setup contracts only, not native menu acceptance or timing proof."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class DogfoodSavedSetupTests(unittest.TestCase):
    def test_explicit_debug_only_setup_without_action_results(self):
        source = (ROOT / 'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG\n'))
        self.assertTrue(source.rstrip().endswith('#endif'))
        self.assertIn('guard AppConfig.isUITesting else { return }', source)
        self.assertIn('guard menus || reorder || cook else { return }', source)
        self.assertIn('store.layout = LibraryLayout()', source)
        self.assertIn('Date().timeIntervalSince1970 * 1000', source)
        self.assertIn('timeMinutes: 25', source)
        for forbidden in ['store.path', '.sort =', '.group =', '.favorite =', '.sortIndex =', 'CookingHistory', 'store.move']:
            self.assertNotIn(forbidden, source)
        startup = (ROOT / 'Ate/App/AteApp.swift').read_text().split('let upgradeRuntime =', 1)[1].split('#else', 1)[0]
        self.assertIn('DogfoodSavedRecipeQAFixtures.prepare(st)', startup)

    def test_real_menu_and_reorder_journeys_retained(self):
        source = (ROOT / 'AteUITests/AteUITests.swift').read_text()
        menus = source.split('func test28_GroupSortAndMenus()', 1)[1].split('func test30_', 1)[0]
        reorder = source.split('func test29_ReorderMyOrder()', 1)[1].split('func testFirstLibrary', 1)[0]
        self.assertIn('-qaSavedRecipesForGroupSort', menus)
        for expected in ['pick("sortMenu", "A–Z")', 'pick("groupByMenu", "Recently added")',
                         'pick("groupByMenu", "Cook time")', 'pick("groupByMenu", "None")',
                         'pick("sortMenu", "Favourites first")', 'XCTAssertLessThan(a.frame.minY, z.frame.minY',
                         'app.buttons["Favourite"].firstMatch.tap()', 'z.press(forDuration: 1.2)',
                         'XCTAssertTrue(app.buttons["Share"].exists)', 'XCTAssertTrue(app.buttons["Add to shopping list"].exists)']:
            self.assertIn(expected, menus)
        for expected in ['-qaSavedRecipesForDogfoodReorder', 'pick("sortMenu", "My order")',
                         'XCTAssertLessThan(second.frame.minY, first.frame.minY', 'first.press(forDuration: 1.2)',
                         'app.buttons["Move up"].tap()', 'XCTAssertLessThan(text("First dish").frame.minY, text("Second dish").frame.minY',
                         'thenDragTo: text("Second dish")']:
            self.assertIn(expected, reorder)
        self.assertNotIn('addNamed(', menus)
        self.assertNotIn('addNamed(', reorder)
