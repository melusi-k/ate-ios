from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class CookPlanRootQueryDiagnosticTests(unittest.TestCase):
    def test_original_entire_test_survives_only_pixels_and_flag(self):
        source = (ROOT / 'AteUITests/CookPlanUITests.swift').read_text()
        source = source.replace(', "-qaCookPlanRootQueryDiagnostic"', '')
        a = source.index('        // Capture pixels before the unchanged')
        b = source.index('        let recipe = ', a)
        original = source[:a] + source[b:]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec')
    def test_bounded_debug_opt_in_root_main_actor_task(self):
        source = (ROOT / 'Ate/Views/LibraryView.swift').read_text()
        diagnostic = source.split('private enum CookPlanRootQueryDiagnostic {',1)[1]
        for token in ['@MainActor', 'AppConfig.isUITesting', '-qaCookPlanRootQueryDiagnostic', '[0.0, 15, 30, 60, 90, 120, 180]', 'Task.sleep', 'Task.isCancelled']:
            self.assertIn(token, diagnostic)
        for token in ['UserDefaults', 'accessibility', 'recipes', 'repository', 'Timer.', 'while ']:
            self.assertNotIn(token, diagnostic)
        self.assertIn('#if DEBUG\n        .task { await CookPlanRootQueryDiagnostic.observeIfRequested', source)
