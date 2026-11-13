from pathlib import Path
import json
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ProductUpdatesTests(unittest.TestCase):
    def test_catalog_is_bundled_with_valid_release_slide_assets(self):
        j = json.loads((ROOT / 'Ate/Resources/ProductUpdates/catalog.json').read_text())
        self.assertEqual(j['schemaVersion'], 1)
        self.assertNotIn('roadmap', j)
        self.assertEqual(len(j['releases']), len({r['id'] for r in j['releases']}))
        for r in j['releases']:
            self.assertLessEqual(len(r['slides']), 5)
            for slide in r['slides']:
                images = ROOT / 'Ate/Resources/Assets.xcassets' / (slide['imageAsset'] + '.imageset')
                for image in json.loads((images / 'Contents.json').read_text())['images']:
                    self.assertTrue((images / image['filename']).is_file())
        self.assertIn('path: Ate/Resources/ProductUpdates\n        type: folder', (ROOT / 'project.yml').read_text())
    def test_local_only_routes_and_preserved_technical_build_notes(self):
        ui = (ROOT / 'Ate/Views/ProductUpdatesViews.swift').read_text()
        model = (ROOT / 'Ate/Logic/ProductUpdates.swift').read_text()
        settings = (ROOT / 'Ate/Views/SettingsView.swift').read_text()
        self.assertIn('ProductReleaseNotesView()', settings)
        self.assertIn('Text(BuildNotes.current)', settings)
        for forbidden in ['Roadmap', 'URLSession', 'Supabase', 'Keychain.', 'UserDefaults', 'Net.', 'Voting', 'vote']:
            self.assertNotIn(forbidden, ui + model)
        for expected in ['Image unavailable', 'Button("Close")', 'Button("Back")', '"Done" : "Next"', 'whatsNew.page']:
            self.assertIn(expected, ui)
