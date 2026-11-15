"""Distinguish input setup failure from actual Explore query retention."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ExploreSearchInputBoundaryTests(unittest.TestCase):
    def test_query_is_entered_once_and_verified_before_leaving_search(self):
        source = (ROOT / 'AteUITests/ExploreUITests.swift').read_text()
        journey = source.split('func testExploreDismissPreservesCollectionAndSearchQuery()', 1)[1]
        self.assertEqual(journey.count('search.typeText("miso")'), 1)
        self.assertNotIn('search.typeText("miso\\n")', journey)
        self.assertLess(journey.index('XCTWaiter.wait(for: [readyForInput], timeout: 5)'), journey.index('search.typeText("miso")'))
        self.assertEqual(journey.count('XCTAssertEqual(search.value as? String, "miso"'), 3)
        self.assertLess(journey.index('The full Search query must land before testing retention'), journey.index('search.typeText("\\n")'))
        self.assertLess(journey.index('Submitting Search must keep the full query'), journey.index('app.tabBars.buttons["Library"].tap()'))
        self.assertIn('Explore must not clear the Search tab query', journey)
        self.assertIn('app.navigationBars["Favourites"].waitForExistence(timeout: 10)', journey)
        self.assertIn('explore-search-query-before-submit', journey)
        self.assertIn('explore-search-query-before-library', journey)
        self.assertNotRegex(journey, r'(?m)^\s*(while|for)\s')
