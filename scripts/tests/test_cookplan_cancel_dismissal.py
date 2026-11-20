"""Source preservation guards only, not native XCTest execution evidence."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
DISMISSAL = '''        // Cancel awaits notification cancellation before dismissing. The underlying
        // plan button can already exist while the sheet still covers recipe detail.
        XCTAssertTrue(reminder.waitForNonExistence(timeout: 10), "Cancel must dismiss the cooking plan sheet before reopening")
'''
REOPENED = '''        XCTAssertTrue(reminder.waitForExistence(timeout: 10), "Reopening after cancellation must mount the cooking plan form")
'''

class CookPlanCancelDismissalTests(unittest.TestCase):
    def source(self):
        return (ROOT / 'AteUITests/CookPlanUITests.swift').read_text()

    def test_cancel_waits_for_dismissal_then_real_reopened_form_before_absence_check(self):
        s = self.source()
        start = s.index('        app.buttons["cookPlan.cancelPlan"].tap()')
        tail = s[start:]
        ordered = [
            'app.buttons["cookPlan.cancelPlan"].tap()',
            'reminder.waitForNonExistence(timeout: 10)',
            'plan.waitForExistence(timeout: 10)',
            'plan.tap()',
            'reminder.waitForExistence(timeout: 10)',
            'XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)',
        ]
        positions = [tail.index(t) for t in ordered]
        self.assertEqual(positions, sorted(positions))
        for t in ['sleep(', 'executionTimeAllowance', 'waitForQuiescence', 'XCTSkip', 'continueAfterFailure = true']:
            self.assertNotIn(t, tail)

    def test_exact_inverse_preserves_all_original_actions_assertions_and_budgets(self):
        s = self.source()
        self.assertEqual(s.count(DISMISSAL), 1)
        self.assertEqual(s.count(REOPENED), 1)
        original = s.replace(DISMISSAL, '', 1).replace(REOPENED, '', 1)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), PARENT_SHA)

PARENT_SHA = '73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec'
