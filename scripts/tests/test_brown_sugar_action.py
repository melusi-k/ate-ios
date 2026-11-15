from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
BASE='bc45b9588799da4eb1c603eb9e6dfe28e5918ed4'
class BrownSugarActionTests(unittest.TestCase):
    def test_original_brown_sugar_test_is_unchanged(self):
        source=(ROOT/'AteTests/GeneratedStepQualityTests.swift').read_text()
        begin='    func testBrownSugarDoesNotBecomeACookingAction() {'
        actual=source.split(begin,1)[1].split('\n    func ',1)[0]
        self.assertEqual(hashlib.sha256(actual.encode()).hexdigest(), '3940b8d0cbc76eb15499e2eb38f7415b978b187e6c1d48f0e2e1c7c2a86ad4df')
        # All original XCTest code stays, not just the failing assertion.
        start=source.index('    func testBrownSugarRubIsNotBrowningButActualBrownCommandIs()')
        end=source.index('    func testHeatVerbAfterFifthWordStillNeedsTimeAndCue()',start)
        self.assertEqual(hashlib.sha256((source[:start]+source[end:]).encode()).hexdigest(), '0f3c608230b9443c2e0396eefcd5c067976e56bad8263ef5dfbe349a0fc3ac4d')
    def test_exact_old_heat_normalization_shared_not_expanded(self):
        s=(ROOT/'Ate/Logic/GeneratedStepQuality.swift').read_text()
        self.assertIn('words(instruction.lowercased().replacingOccurrences(of: "brown sugar", with: "sugar"))',s)
        self.assertIn('let method = cookingActionWords(steps[0].instruction)',s)
        self.assertIn('guard !cookingActionWords(step.instruction).isDisjoint(with: heatActions) else { continue }',s)
        self.assertNotIn('let method = words(steps[0].instruction)',s)
        self.assertEqual(s.count('.replacingOccurrences(of: "brown sugar", with: "sugar")'),1)
