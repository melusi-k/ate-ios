"""Read-only, bounded fixture diagnostics must not alter animation or UI acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class LibraryAnimationDiagnosticTests(unittest.TestCase):
    def test_sampling_is_bounded_and_explicit_group_fixture_only(self):
        s = (ROOT / 'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('guard AppConfig.isUITesting else { return }', s)
        self.assertIn('if menus { startAnimationDiagnostics() }', s)
        self.assertIn('guard !diagnosticsStarted else { return }', s)
        self.assertIn('for offset in [15.0, 30, 45, 60, 90, 120]', s)
        self.assertIn('visited < 2048, depth < 64', s)
        self.assertIn('emitted < 64', s)
        self.assertIn('.prefix(8)', s)
        diagnostic = s.split('@MainActor private static func recordAnimations', 1)[1].split('private static func card', 1)[0]
        for forbidden in ['removeAnimation', 'removeAllAnimations', 'speed =', 'isEnabled =', 'store.', 'layer.name', '.text', '.label']:
            self.assertNotIn(forbidden, diagnostic)
        self.assertIn('coversLoading=', diagnostic)
