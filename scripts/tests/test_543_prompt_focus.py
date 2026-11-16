from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
ADDITION='        // A returned tap does not prove that the editor owns keyboard input.\n        // Fail before the single type event if focus never arrived; never retap\n        // or retype to hide a missed setup interaction.\n        let promptFocus = XCTNSPredicateExpectation(\n            predicate: NSPredicate { object, _ in\n                guard let editor = object as? XCUIElement,\n                      editor.responds(to: NSSelectorFromString("hasKeyboardFocus")),\n                      editor.value(forKey: "hasKeyboardFocus") as? Bool == true else { return false }\n                return self.app.keyboards.firstMatch.exists\n            }, object: prompt)\n        XCTAssertEqual(XCTWaiter.wait(for: [promptFocus], timeout: 5), .completed,\n                       "Prompt editor must own keyboard focus before the single recipe input")\n'
class PromptFocus543(unittest.TestCase):
    def test_original_journey_reconstructs_and_mutants_fail(self):
        def restore(s):
            assert s.count(ADDITION)==1
            s=s.replace(ADDITION,'',1)
            assert hashlib.sha256(s.encode()).hexdigest()=='89cfd7a8c575d3a492db9b0e7ec123a3aa6204e74495b65a21a17b5eebac92e9'
        s=(ROOT/'AteUITests/InsightsAcceptanceUITests.swift').read_text();restore(s)
        for changed in [s.replace(ADDITION,'',1),s+ADDITION,s.replace('XCTAssertLessThan(weeklyCard.frame.minX','XCTAssertGreaterThan(weeklyCard.frame.minX',1)]:
            with self.assertRaises(AssertionError):restore(changed)
    def test_focus_boundary_has_no_input_retry_or_budget_increase(self):
        self.assertIn('hasKeyboardFocus',ADDITION)
        self.assertIn('keyboards.firstMatch.exists',ADDITION)
        self.assertIn('timeout: 5',ADDITION)
        for token in ['.tap(','.typeText(', 'sleep(', 'executionTimeAllowance','while ']:self.assertNotIn(token,ADDITION)
