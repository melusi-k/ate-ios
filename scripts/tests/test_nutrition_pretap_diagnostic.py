from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class NutritionPretapDiagnosticTests(unittest.TestCase):
    def test_original_journey_survives_only_evidence_and_flag_insertion(self):
        source = (ROOT / 'AteUITests/NutritionDiaryUITests.swift').read_text()
        body = source.split('func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch() throws {',1)[1].split('\n    func ',1)[0]
        body = body.replace(', "-qaNutritionPretapDiagnostic"', '')
        a = body.index('        // Pixels before the unchanged')
        b = body.index('        typeAfterKeyboard(', a)
        original = body[:a] + body[b:]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '8a25cbb0108ee51e75d0a1266d575d0107326947bf4ad463ab442edc90c1c59e')
    def test_debug_opt_in_bounded_no_ui_or_data_reads(self):
        source = (ROOT / 'Ate/Views/NutritionDiaryView.swift').read_text()
        diagnostic = source.split('private enum NutritionPretapDiagnostic {',1)[1]
        for token in ['@MainActor', 'AppConfig.isUITesting', '-qaNutritionPretapDiagnostic', '[0.0, 15, 30, 60, 90, 120, 180, 210]', 'Task.sleep', 'Task.isCancelled']:
            self.assertIn(token, diagnostic)
        for token in ['UserDefaults', 'accessibility', 'entries', 'repository', 'Timer.', 'while ']:
            self.assertNotIn(token, diagnostic)
        self.assertIn('#if DEBUG\n        .task { await NutritionPretapDiagnostic.observeIfRequested() }\n        #endif', source)
