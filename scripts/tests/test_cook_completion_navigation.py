"""Completion must be acknowledged before querying the recipe detail's root tabs."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]


class CookCompletionNavigationTests(unittest.TestCase):
    def test_completion_confirms_record_then_dismisses_before_returning_to_history(self):
        source = (ROOT / 'AteUITests/AteUITests.swift').read_text()
        case = source.split('func testCookModeCompletionRecordsCookingDay()', 1)[1].split('\n    private func openTodayCookedSheet', 1)[0]
        actions = ['finish.tap()', 'wait(app.staticTexts["cookCompletion.recorded"], 5)',
                   'completionDone.tap()', 'wait(app.buttons["Cook mode"], 5)',
                   'tabFromRecipeDetail("Journal", recipeTitle: "Miso salmon for two")']
        positions = [case.index(action) for action in actions]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('XCTAssertEqual(app.buttons.matching(identifier: "cookReflection.notNow").count, 1)', case)
        self.assertNotIn('tab("Journal")', case)
        self.assertIn('tracker.day.', case)
        self.assertIn('XCTAssertTrue', case)
        self.assertIn('cooked', case)
