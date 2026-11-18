"""Source-only audit regression. Native pixels/AX remain UNRUN."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AuditSlice(unittest.TestCase):
    def test_authorized_source_change(self):
        import json
        d=json.loads((ROOT/'Ate/Resources/ProductUpdates/catalog.json').read_text())
        self.assertEqual([r['id'] for r in d['releases']],['product-updates-introduction'])
        for release in d['releases']:
            self.assertEqual(release['version'],'0.1.0')
            for slide in release['slides']:
                self.assertFalse(slide['placeholder'])
                self.assertEqual(slide['imageAsset'],'ProductUpdatesBrand')
                self.assertEqual(slide['imageAlt'],'Ate logo.')
        self.assertFalse((ROOT/'Ate/Resources/Assets.xcassets/ProductUpdatesPlaceholder.imageset').exists())
    def test_additive_inverse_is_exact_and_fails_closed(self):
        from audit_updates_content_delta import restore,PATH,BASE
        import hashlib
        raw=(ROOT/PATH).read_text()
        self.assertEqual(hashlib.sha256(restore(PATH,raw).encode()).hexdigest(),BASE)
        for changed in [raw+'// mutation',raw.replace('Dismiss','Try again',1) if 'Dismiss' in raw else raw+' ']:
            with self.assertRaises(AssertionError):restore(PATH,changed)
