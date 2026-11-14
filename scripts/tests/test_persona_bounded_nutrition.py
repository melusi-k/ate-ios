from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PersonaBoundedNutritionTests(unittest.TestCase):
    def test_exact_persona_contract_and_original_prompt_limits(self):
        source=(ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        shared=source.split('static let instructions = """\n',1)[1].split('\n    """',1)[0]
        shared='\n'.join(x[4:] if x.startswith('    ') else x for x in shared.splitlines())
        self.assertIn('South African home-cooking expert',shared)
        self.assertLessEqual(len(shared),3450)
        for mode,brief in re.findall(r'case \.(\w+): brief = "(.*)"',source):
            self.assertLessEqual(len(shared)+1+len(brief),3900,mode)
        for term in ['10. Keep dependency order', '2 carrots, grated', 'bake at 160°C', 'at least 4 real ingredients']:
            self.assertIn(term,shared)
    def test_failed_save_persistence_keeps_two_writes_cancel_and_real_relaunch(self):
        s=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        part=s.split('func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch()',1)[1].split('func testCorruptDiary',1)[0]
        self.assertLess(part.index('returnKey.tap()'),part.index('for _ in 0..<2'))
        for term in ['returnKey.waitForExistence(timeout: 2)', 'app.keyboards.firstMatch.waitForNonExistence(timeout: 5)', 'for _ in 0..<2', 'tapWhenHittable(save', 'scrollToHittable(formError', 'XCTAssertEqual(formError.label', 'app.navigationBars.buttons["Cancel"].tap()', 'app.terminate()', 'relaunched.launchArguments = ["-UITesting"]', 'openDiary(relaunched)', 'captureNutritionState(relaunched']:
            self.assertIn(term,part)
        self.assertNotIn('executionTimeAllowance',part)
