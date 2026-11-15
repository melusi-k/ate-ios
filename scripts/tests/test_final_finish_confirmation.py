from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
BLOCK='''        wait(app.staticTexts["cookCompletion.recorded"], 5)
        let completionDone = app.buttons["cookReflection.notNow"]
        wait(completionDone, 5)
        XCTAssertEqual(app.buttons.matching(identifier: "cookReflection.notNow").count, 1)
        completionDone.tap()
'''
def restore_final_finish_confirmation(test, source):
    case=source.split('    func test06b_CookModeFinalStepAndFinish() {',1)[1].split('\n    func ',1)[0]
    test.assertEqual(case.count(BLOCK),1)
    # Restrict normalization to this case. Other completion tests stay intact.
    restored=case.replace(BLOCK,'',1)
    return source.replace(case,restored,1)
class FinalFinishConfirmationTests(unittest.TestCase):
    def test_all_original_ui_code_preserved(self):
        source=(ROOT/'AteUITests/AteUITests.swift').read_text()
        self.assertEqual(hashlib.sha256(restore_final_finish_confirmation(self,source).encode()).hexdigest(), '44b91411ce19e71986601f66cb461efb248e953004f87ca67382432ef765d9ca')
    def test_finish_records_then_done_before_original_arrival(self):
        case=(ROOT/'AteUITests/AteUITests.swift').read_text().split('    func test06b_CookModeFinalStepAndFinish() {',1)[1].split('\n    func ',1)[0]
        actions=['finish.tap()', 'wait(app.staticTexts["cookCompletion.recorded"], 5)', 'wait(completionDone, 5)', 'XCTAssertEqual(app.buttons.matching(identifier: "cookReflection.notNow").count, 1)', 'completionDone.tap()', 'wait(app.buttons["Cook mode"], 5)']
        positions=[case.index(action) for action in actions]
        self.assertEqual(positions,sorted(positions))
        self.assertIn('wait(text("Step 4 of 4"))',case)
        self.assertIn('XCTAssertFalse(app.buttons["Next step"].exists',case)
        self.assertIn('XCTAssertEqual(finish.label, "Finish cooking")',case)
