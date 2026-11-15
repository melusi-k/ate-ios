from pathlib import Path
import subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]
BASE='bc45b9588799da4eb1c603eb9e6dfe28e5918ed4'
class BrownSugarActionTests(unittest.TestCase):
    def test_original_brown_sugar_test_is_unchanged(self):
        baseline=subprocess.check_output(['git','show',BASE+':AteTests/GeneratedStepQualityTests.swift'],cwd=ROOT,text=True)
        source=(ROOT/'AteTests/GeneratedStepQualityTests.swift').read_text()
        begin='    func testBrownSugarDoesNotBecomeACookingAction() {'
        original=baseline.split(begin,1)[1].split('\n    func ',1)[0]
        actual=source.split(begin,1)[1].split('\n    func ',1)[0]
        self.assertEqual(actual,original)
        # All original XCTest code stays, not just the failing assertion.
        start=source.index('    func testBrownSugarRubIsNotBrowningButActualBrownCommandIs()')
        end=source.index('    func testHeatVerbAfterFifthWordStillNeedsTimeAndCue()',start)
        self.assertEqual(source[:start]+source[end:],baseline)
    def test_exact_old_heat_normalization_shared_not_expanded(self):
        s=(ROOT/'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('words(instruction.lowercased().replacingOccurrences(of: "brown sugar", with: "sugar"))',s)
        self.assertIn('let method = cookingActionWords(steps[0].instruction)',s)
        self.assertIn('guard !cookingActionWords(step.instruction).isDisjoint(with: heatActions) else { continue }',s)
        self.assertNotIn('let method = words(steps[0].instruction)',s)
        self.assertEqual(s.count('.replacingOccurrences(of: "brown sugar", with: "sugar")'),1)
