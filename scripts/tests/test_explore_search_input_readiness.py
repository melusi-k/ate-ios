"""Source contracts only. The native Explore journey remains the acceptance gate."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ExploreSearchInputReadinessTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / 'AteUITests/ExploreUITests.swift').read_text()
        self.journey = source.split('func testExploreDismissPreservesCollectionAndSearchQuery()', 1)[1]

    def test_single_input_has_bounded_exact_readiness_before_submit(self):
        journey = self.journey
        self.assertEqual(journey.count('search.typeText("miso")'), 1)
        self.assertEqual(journey.count('search.typeText("\\n")'), 1)
        self.assertIn('predicate: NSPredicate(format: "value == %@", "miso"), object: search', journey)
        self.assertIn('XCTAssertEqual(XCTWaiter.wait(for: [fullQuery], timeout: 5), .completed', journey)
        self.assertLess(journey.index('search.typeText("miso")'), journey.index('let fullQuery'))
        self.assertLess(journey.index('XCTWaiter.wait(for: [fullQuery]'), journey.index('shot("explore-search-query-before-submit")'))
        self.assertLess(journey.index('XCTWaiter.wait(for: [fullQuery]'), journey.index('search.typeText("\\n")'))
        self.assertNotRegex(journey, r'\b(?:sleep|usleep|while|repeat)\s*\(')
        self.assertEqual(re.findall(r'timeout: (\d+)', journey), ['10', '5', '5', '5', '10', '10', '10'])

    def test_all_three_exact_query_assertions_remain(self):
        self.assertEqual(self.journey.count('XCTAssertEqual(search.value as? String, "miso"'), 3)
        for message in [
            'The full Search query must land before testing retention',
            'Submitting Search must keep the full query before opening Explore',
            'Explore must not clear the Search tab query',
        ]:
            self.assertIn(message, self.journey)

    def test_focus_and_keyboard_share_the_existing_pretyping_budget(self):
        journey = self.journey
        self.assertIn('NSSelectorFromString("hasKeyboardFocus")', journey)
        self.assertIn('XCTAssertTrue(search.responds(to: focusSelector)', journey)
        self.assertIn('field.responds(to: focusSelector)', journey)
        self.assertIn('(field.value(forKey: "hasKeyboardFocus") as? Bool) == true else { return false }', journey)
        self.assertIn('return keyboard.exists', journey)
        self.assertIn('XCTWaiter.wait(for: [readyForInput], timeout: 5)', journey)
        self.assertLess(journey.index('XCTWaiter.wait(for: [readyForInput]'), journey.index('search.typeText("miso")'))
        self.assertNotIn('keyboard.waitForExistence', journey)
