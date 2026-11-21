"""The failing journey changes one route choice, never its persistence checks."""
from pathlib import Path
import hashlib
import json
import unittest
from nutrition_log_route_delta import restore

ROOT = Path(__file__).resolve().parents[2]
PATH = 'AteUITests/NutritionDiaryUITests.swift'

class NutritionLogRouteTests(unittest.TestCase):
    def test_exact_one_journey_inverse_and_mutants_fail_closed(self):
        contract = json.loads((ROOT/'scripts/tests/nutrition_log_route_inverse.json').read_text())
        source = (ROOT/PATH).read_text()
        original = restore(PATH, source)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), contract['parent_sha'])
        self.assertEqual(source.replace(contract['new'], contract['old'], 1), original)
        self.assertIn('startupDiagnosticMark("open-log-form-start")', contract['new'])
        self.assertNotIn('accessoryAdd', contract['new'])
        self.assertIn('app.navigationBars["Food diary"].buttons["nutritionDiary.add"]', contract['new'])
        self.assertIn('logFood.isHittable', contract['new'])
        self.assertIn('logFood.tap()', contract['new'])
        self.assertIn('nutritionDiary.foodName', contract['new'])
        self.assertIn('waitForExistence(timeout: 5)', contract['new'])
        for mutant in [source.replace(contract['new'], '', 1), source+contract['new'], source+'// unrelated\n']:
            with self.assertRaises(AssertionError):
                restore(PATH, mutant)

    def test_all_post_form_steps_are_byte_identical(self):
        contract = json.loads((ROOT/'scripts/tests/nutrition_log_route_inverse.json').read_text())
        source = (ROOT/PATH).read_text()
        original = restore(PATH, source)
        start = '        startupDiagnosticMark("open-log-form-end")'
        self.assertEqual(source.split(start, 1)[1], original.split(start, 1)[1])
        body = source.split('func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch()', 1)[1].split('\n    func ',1)[0]
        for token in ['for _ in 0..<2', 'Each failed write must show its error before cancellation', 'app.terminate()', 'relaunched.launch()', 'Failed save should leave the relaunched diary empty']:
            self.assertIn(token, body)
        self.assertNotIn('sleep(', contract['new'])
        self.assertEqual(contract['new'].count('.tap()'), 1)

if __name__ == '__main__':
    unittest.main()
