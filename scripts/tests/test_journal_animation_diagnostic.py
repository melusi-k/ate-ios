"""Journal diagnostic observes public layer state without changing native acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class JournalAnimationDiagnosticTests(unittest.TestCase):
    def test_debug_and_explicit_journey_only_with_hard_bounds(self):
        s = (ROOT / 'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('ProcessInfo.processInfo.arguments.contains("-qaJournalAnimationDiagnostic")', s)
        self.assertIn('!diagnosticsStarted else { return }', s)
        self.assertIn('[15.0, 25, 45, 75, 105, 135, 165, 195, 225]', s)
        self.assertIn('visited < 2048, depth < 64', s)
        self.assertIn('emitted < 64', s)
        self.assertIn('.prefix(8)', s)
        diagnostic = s.split('enum JournalAnimationDiagnostics {', 1)[1]
        for bad in ['removeAnimation', 'removeAllAnimations', 'speed =', 'isEnabled =', 'store.', 'layer.name', '.text', '.label']:
            self.assertNotIn(bad, diagnostic)
        tests = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        self.assertEqual(tests.count('"-qaJournalAnimationDiagnostic"'), 1)
