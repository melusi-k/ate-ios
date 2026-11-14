from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
NAMES = ['test28_GroupSortAndMenus', 'test28_GroupRecentlyAdded', 'test28_GroupCookTime',
         'test28_FavouriteSwipeAndSort', 'test28_ContextMenuAddsShoppingAndShowsFeedback',
         'test29_ReorderMyOrder', 'test29_DragMyOrder']

class LibraryIndependentJourneyTests(unittest.TestCase):
    def test_every_journey_starts_clean_and_ci_requires_its_named_pass(self):
        source = (ROOT / 'AteUITests/AteUITests.swift').read_text()
        workflow = (ROOT / '.github/workflows/dogfood-qualification.yml').read_text()
        for name in NAMES:
            body = source.split('    func ' + name + '() {', 1)[1].split('\n    func ', 1)[0]
            flags = {
                'test28_GroupSortAndMenus': '-qaSavedRecipesForGroupSort',
                'test28_GroupRecentlyAdded': '-qaSavedAppleForGroup',
                'test28_GroupCookTime': '-qaSavedAppleForGroup',
                'test28_FavouriteSwipeAndSort': '-qaSavedRecipesForFavourite',
                'test28_ContextMenuAddsShoppingAndShowsFeedback': '-qaSavedZestyForContext',
                'test29_ReorderMyOrder': '-qaSavedRecipesForDogfoodReorder',
                'test29_DragMyOrder': '-qaSavedRecipesForDogfoodReorder',
            }
            self.assertIn('launch(["' + flags[name] + '"])', body)
            self.assertNotIn('addNamed(', body)
            self.assertIn('-only-testing:AteUITests/AteUITests/' + name + ' \\', workflow)
        self.assertIn('for test in ' + ' '.join(NAMES) + '; do', workflow)
        self.assertIn('"$total" -lt 16', workflow)
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480', workflow)
        self.assertNotIn('retry', workflow.split('xcodebuild test -project', 1)[1].split('- name: Retain UI-test photo-import', 1)[0])

    def test_original_outcomes_and_short_toast_assertion_remain(self):
        source = (ROOT / 'AteUITests/AteUITests.swift').read_text()
        for outcome in ['"A–Z order"', '"section.Today"', '"section.Under 30 min"',
                        'pick("groupByMenu", "None")', '"Added to Favourites"',
                        'pick("sortMenu", "Favourites first")', 'app.buttons["Cook"]',
                        'app.buttons["Share"].exists', 'app.buttons["Add to shopping list"].exists',
                        '"Added to your shopping list"', '"new (unordered) cards newest first"',
                        'app.buttons["Move up"].tap()', '"moved up"', '"library-reorder-drag"']:
            self.assertIn(outcome, source)
        toast = source.split('func test28_ContextMenuAddsShoppingAndShowsFeedback()', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('feedback.waitForExistence(timeout: 3)', toast)
        self.assertIn('XCTAssertTrue(appeared', toast)
        self.assertLess(toast.index('feedback.waitForExistence'), toast.index('shot("library-context-shopping-feedback-assertion")'))
        self.assertLess(toast.index('app.debugDescription'), toast.index('XCTAssertTrue(appeared'))
        self.assertIn('evidence.lifetime = .keepAlways', toast)
