from pathlib import Path
import importlib.util
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ProductRoadmapTests(unittest.TestCase):
    def test_empty_reviewed_bundle_and_enabled_settings_reader(self):
        catalog = json.loads((ROOT / 'Ate/Resources/ProductUpdates/roadmap.json').read_text())
        self.assertEqual(catalog, {'schemaVersion': 1, 'features': []})
        self.assertIn('ProductRoadmapView()', (ROOT / 'Ate/Views/SettingsView.swift').read_text())
        self.assertIn('path: Ate/Resources/ProductUpdates\n        type: folder', (ROOT / 'project.yml').read_text())
        source = (ROOT / 'Ate/Logic/ProductRoadmap.swift').read_text()
        self.assertIn('case considering, planned, building, released', source)
        self.assertIn('static let available = false', source)
        self.assertIn('No vote has been sent or saved', source)
        ui = (ROOT / 'Ate/Views/ProductRoadmapView.swift').read_text()
        for text in ['.disabled(!ProductRoadmapVoting.available)', 'roadmap.empty', 'roadmap.unavailable', '.pageWidth()', '.cardSurface(padding: 16)']:
            self.assertIn(text, ui)
        for forbidden in ['URLSession', 'Supabase', 'Keychain', 'UserDefaults', 'Net.', 'AsyncImage', 'voteCount', 'pendingVotes']:
            self.assertNotIn(forbidden, source + ui)

    def test_selected_native_journey_has_own_required_nonzero_log_and_screenshots(self):
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/InsightsPresentationUITests/testSettingsRoadmapEmptyCatalogAndUnavailableVotingAtNormalText', workflow)
        self.assertIn('required_logs: roadmap-reader.log', workflow)
        self.assertIn('python3 scripts/verify-roadmap-reader-results.py roadmap-reader.log', workflow)
        self.assertIn('roadmap-reader-attachments', workflow)
        spec = importlib.util.spec_from_file_location('roadmap_verifier', ROOT / 'scripts/verify-roadmap-reader-results.py')
        verifier = importlib.util.module_from_spec(spec); spec.loader.exec_module(verifier)
        passed = "Test Case '-[AteUITests.InsightsPresentationUITests testSettingsRoadmapEmptyCatalogAndUnavailableVotingAtNormalText]' passed (10.2 seconds).\n** TEST EXECUTE SUCCEEDED **"
        self.assertEqual(verifier.verify(passed), 1)
        for text in ['', passed.replace('10.2', '0.0'), passed.replace('passed', 'failed'), passed + passed, passed.replace('testSettingsRoadmapEmptyCatalogAndUnavailableVotingAtNormalText', 'other')]:
            with self.assertRaises(ValueError): verifier.verify(text)
