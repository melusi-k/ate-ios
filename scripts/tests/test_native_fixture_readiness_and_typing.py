"""Keep native fixtures deterministic and UI input single-shot, not product mocks."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class NativeFixtureReadinessAndTypingTests(unittest.TestCase):
    def test_generation_backend_installs_continuation_before_signalling_readiness(self):
        source = (ROOT / 'AteTests/DraftGenerationAttemptTests.swift').read_text()
        fixture = source.split('private final class DelayedBackend', 1)[1].split('    func test', 1)[0]
        self.assertLess(fixture.index('continuation = $0'), fixture.index('ready()'))
        self.assertIn('@MainActor\n    private final class DelayedBackend', source)
        self.assertEqual(source.count('.parse(ready: {'), 5)
        self.assertNotIn('.parse()', source)
        self.assertEqual(source.count('timeout: 2'), 10)
        self.assertIn('XCTAssertEqual(drafts.pending?.text, "Retained request")', source)
        self.assertIn('XCTAssertEqual(effects, 0)', source)
        self.assertIn('XCTAssertTrue(cards.isEmpty)', source)

    def test_nutrition_input_replaces_whole_value_once_without_replay(self):
        source = (ROOT / 'AteUITests/NutritionDiaryUITests.swift').read_text()
        helper = source.split('private func typeAfterKeyboard', 1)[1].split('    func testFoodDiary', 1)[0]
        self.assertEqual(helper.count('element.typeText(text)'), 1)
        self.assertNotIn('doubleTap()', helper)
        self.assertIn('current != element.placeholderValue', helper)
        self.assertIn('app.menuItems["Select All"]', helper)
        self.assertIn('guard selectAll.waitForExistence(timeout: 5), selectAll.isHittable else', helper)
        self.assertLess(helper.index('selectAll.tap()'), helper.index('element.typeText(text)'))
        self.assertIn('if landed != text', helper)
        self.assertIn('XCTFail("Typed text did not land in the field', helper)
        self.assertIn('typeAfterKeyboard-missed', helper)
        self.assertIn('XCTAssertEqual(app.textFields["nutritionDiary.foodName"].value as? String, "My lunch")', source)
