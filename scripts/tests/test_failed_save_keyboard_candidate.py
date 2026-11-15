"""Candidate adds editing completion without removing the original journey."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class FailedSaveKeyboardCandidateTests(unittest.TestCase):
    def test_candidate_is_only_a_keyboard_completion_insertion(self):
        source = (ROOT / 'AteUITests/NutritionDiaryUITests.swift').read_text()
        body = source.split('func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch() throws {', 1)[1].split('\n    func ', 1)[0]
        start = body.index('        // Finish editing through the real keyboard')
        end = body.index('        let save = ', start)
        addition = body[start:end]
        self.assertIn('returnKey.tap()', addition)
        self.assertIn('XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5)', addition)
        original = body[:start] + body[end:]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '8a25cbb0108ee51e75d0a1266d575d0107326947bf4ad463ab442edc90c1c59e')
