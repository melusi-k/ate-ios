from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ExploreBoundedRetention(unittest.TestCase):
    def test_menu_assertions_remain_in_separate_real_ui_test(self):
        source = (ROOT / 'AteUITests/ExploreUITests.swift').read_text()
        menu = source.split('func testExploreDismissPreservesSelectedCollection()',1)[1].split('func testExploreDismissPreservesCollectionAndSearchQuery()',1)[0]
        for phrase in ['app.buttons["libraryBrowseMenu"].tap()',
                       'app.collectionViews.containing(NSPredicate(format: "label == %@", "Collections"))',
                       'XCTAssertTrue(menu.waitForExistence(timeout: 5))',
                       'let favourite = menu.buttons.matching(NSPredicate(format: "label == %@", "Favourites"))',
                       'XCTAssertEqual(favourite.count, 1)', 'favourite.element(boundBy: 0).tap()',
                       'open();', 'app.buttons["explore.done"].tap()']:
            self.assertIn(phrase, menu)
        self.assertEqual(menu.count('app.navigationBars["Favourites"].waitForExistence(timeout: 10)'), 2)
        search = source.split('func testExploreDismissPreservesCollectionAndSearchQuery()',1)[1]
        self.assertNotIn('libraryBrowseMenu', search)
        self.assertNotIn('saveRecipe()', search)
        self.assertIn('saveRecipe(); open()', source, 'ordinary add/save journey still covered separately')

    def test_fixture_cannot_fill_query_or_skip_explore_ui(self):
        source = (ROOT / 'Ate/App/ExploreRetentionQAFixtures.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG'))
        self.assertIn('guard isUITesting, arguments.contains("-qaExploreRetentionSaved") else { return nil }', source)
        self.assertIn('if mode == .favourites { store.filter.collection = .favourites }', source)
        for forbidden in ['store.search', 'searchQuery', 'showExplore', 'UserDefaults', 'favorite: true']:
            self.assertNotIn(forbidden, source)
        app = (ROOT / 'Ate/App/AteApp.swift').read_text()
        self.assertIn('ExploreRetentionQAFixtures.prepare(st)', app.split('#if DEBUG',1)[1].split('#else',1)[0])
