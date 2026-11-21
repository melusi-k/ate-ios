from nutrition_log_route_delta import restore as restore_nutrition_route
"""Candidate adds editing completion without removing the original journey."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class FailedSaveKeyboardCandidateTests(unittest.TestCase):
    def test_candidate_is_only_a_keyboard_completion_insertion(self):
        source = restore_nutrition_route('AteUITests/NutritionDiaryUITests.swift', (ROOT / 'AteUITests/NutritionDiaryUITests.swift').read_text())
        body = source.split('func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch() throws {', 1)[1].split('\n    func ', 1)[0]
        start = body.index('        // Finish editing through the real keyboard')
        end = body.index('        let save = ', start)
        addition = body[start:end]
        self.assertIn('returnKey.tap()', addition)
        self.assertIn('XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5)', addition)
        original = body[:start] + body[end:]
        # Composed head: also reverse #535's diagnostic additions in this body exactly.
        original = '\n'.join(line for line in original.split('\n') if 'startupDiagnosticMark(' not in line)
        original = original.replace(', "-qaNutritionPretapDiagnostic"', '').replace(', "-qaStartupLivenessDiagnostic"', '')
        a = original.index('        // Pixels before the unchanged')
        b = original.index('        typeAfterKeyboard(', a)
        original = original[:a] + original[b:]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '8a25cbb0108ee51e75d0a1266d575d0107326947bf4ad463ab442edc90c1c59e')
