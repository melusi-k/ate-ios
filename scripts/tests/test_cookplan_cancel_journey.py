"""Prove dismissal and new sheet presence, retain cancellation absence assertion."""
from pathlib import Path
import hashlib
import json
import unittest
from cookplan_cancel_journey_delta import restore
ROOT = Path(__file__).resolve().parents[2]
class CookPlanCancelJourneyTests(unittest.TestCase):
    def test_exact_inverse_and_strict_phase_checks(self):
        c = json.loads((ROOT/'scripts/tests/cookplan_cancel_journey_inverse.json').read_text())
        source = (ROOT/c['path']).read_text()
        self.assertEqual(hashlib.sha256(restore(c['path'], source).encode()).hexdigest(), c['parent_sha256'])
        new = c['new']
        ordered = ['app.buttons["cookPlan.cancelPlan"].tap()', 'reminder.waitForNonExistence(timeout: 10)', 'plan.waitForExistence(timeout: 10)', 'plan.isHittable', 'plan.tap()', 'reminder.waitForExistence(timeout: 10)', 'XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)']
        indexes = [new.index(x) for x in ordered]
        self.assertEqual(indexes, sorted(indexes))
        self.assertIn(c['old'].splitlines()[-1], new)
        self.assertNotIn('sleep(', new)
        self.assertNotIn('try?', new)
        self.assertEqual(new.count('plan.tap()'), 1)
        from cookplan_cancel_phase_delta import restore as restore_cancel_phases
        source = restore_cancel_phases(c['path'], source)
        for mutant in [source.replace(c['new'], '', 1), source+c['new'], source+'// unrelated', source.replace('reminder.waitForNonExistence(timeout: 10)', 'reminder.waitForNonExistence(timeout: 20)', 1)]:
            with self.assertRaises(AssertionError): restore(c['path'], mutant)
