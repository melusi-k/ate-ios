from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
INVERSE=[['        // The underlying recipe action can exist while cancellation is still\n        // dismissing the old sheet. Do not send the reopen tap through it.\n        XCTAssertTrue(app.switches["cookPlan.reminder"].waitForNonExistence(timeout: 10),\n                      "Cancel must dismiss the old cooking plan sheet before reopening")\n', ''], ['        XCTAssertTrue(plan.isHittable, "The recipe planning action must be reachable after cancellation")\n', ''], ['        XCTAssertTrue(app.switches["cookPlan.reminder"].waitForExistence(timeout: 10),\n                      "Reopen must mount a new cooking plan sheet before checking cancellation")\n', '']]
class CookPlanReopen551(unittest.TestCase):
    def test_exact_original_ui_restored_and_mutants_refused(self):
        def restore(raw):
            for new,old in INVERSE:
                assert raw.count(new)==1
                raw=raw.replace(new,old,1)
            assert hashlib.sha256(raw.encode()).hexdigest()=='73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec'
            return raw
        raw=(ROOT/'AteUITests/CookPlanUITests.swift').read_text();restore(raw)
        for new,old in INVERSE:
            for changed in [raw.replace(new,'',1),raw+new,raw.replace('XCTAssertFalse','XCTAssertTrue',1),raw.replace('timeout: 10','timeout: 11',1)]:
                with self.assertRaises(AssertionError):restore(changed)
    def test_cancel_dismiss_and_new_sheet_precede_original_absence(self):
        raw=(ROOT/'AteUITests/CookPlanUITests.swift').read_text().split('app.buttons["cookPlan.cancelPlan"].tap()',1)[1]
        tokens=['waitForNonExistence(timeout: 10)','XCTAssertTrue(plan.isHittable','plan.tap()','waitForExistence(timeout: 10),','XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)']
        positions=[raw.index(t) for t in tokens];self.assertEqual(positions,sorted(positions))
