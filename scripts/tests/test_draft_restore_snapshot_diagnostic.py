"""Observe synthetic draft restoration without replacing persistence assertions."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class DraftRestoreSnapshotDiagnosticTests(unittest.TestCase):
    def test_observation_is_explicit_and_bounded(self):
        s = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        block = s.split('private struct DraftRestoreSnapshotDiagnostics: Sendable {', 1)[1]
        self.assertIn('guard AppConfig.isUITesting,', block)
        self.assertIn('contains("-qaDraftRestoreSnapshotDiagnostic")', block)
        self.assertIn('[15.0, 30, 60, 90, 120, 180]', block)
        for bad in ['DraftStore.', 'store.', 'UserDefaults', 'remove', 'withAnimation', 'recipe.']:
            self.assertNotIn(bad, block)
        tests = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        self.assertEqual(tests.count('"-qaDraftRestoreSnapshotDiagnostic"'), 1)
        self.assertIn('XCTAssertFalse(text("Restored your unsaved card").exists, "saved draft must not come back")', tests)
