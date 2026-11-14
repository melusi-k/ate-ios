"""Only redundant recipe creation changes; acceptance actions are byte-preserved."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SavedLibraryPreconditionsTests(unittest.TestCase):
    def test_every_original_action_and_assertion_is_retained(self):
        path = 'AteUITests/AteUITests.swift'
        current = (ROOT / path).read_text()
        # Immutable post-setup body digests from exact 94b6149aa6bfc117bac138dc4c60cac298d15c61.
        # Cover EVERY original action, assertion, wait, screenshot and comment after setup.
        # Self-contained in depth-1/credential-free checkouts; history is never consulted.
        expected = {
            'test28_GroupSortAndMenus': '9c1ce401791d6877bd86de33d6f07174e3bc96bbc18fbd7ea8eed3ce6d6bb2c4',
            'test28_GroupRecentlyAdded': '58a69a22662716742af0f289a30ad162b7f86e3a2fd4858626d14d3f6e300810',
            'test28_GroupCookTime': 'f74c0cb56f22c4f23a794f185c0819eab815c909f700b34309d7d6a870514b66',
            'test28_FavouriteSwipeAndSort': '67cc85b77dbbc01f1d7578b201e7a6ae3913aecbc4fbac2338b1d6c23fd43eef',
            'test28_ContextMenuAddsShoppingAndShowsFeedback': '13b84f99a0d30587a29e2bce0e1951cf4023d9342407df117492263105eb7060',
            'test29_ReorderMyOrder': '10f2e06db4dc02c06584eb0a09cb1de4460e3b77ac69ffba1bde20ae23981f21',
            'test29_DragMyOrder': '6869fd97d9273b2942dabc8cbd307a6dde3795daf754568d71589d918401d1b8',
        }
        for name, digest in expected.items():
            lines = current.split('    func ' + name + '() {', 1)[1].split('\n    }', 1)[0].splitlines()
            unchanged = '\n'.join(line for line in lines if not any(x in line for x in ['launch(', 'addNamed(', '// Saved-only setup']))
            self.assertEqual(hashlib.sha256(unchanged.encode()).hexdigest(), digest, name)

    def test_sampler_cannot_change_animation_or_preselect_results(self):
        s = (ROOT / 'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertTrue(s.startswith('#if DEBUG'))
        self.assertIn('guard AppConfig.isUITesting else { return }', s)
        for bad in ['layout.sort =', 'layout.group =', 'favorite:', 'sortIndex:', 'removeAllAnimations', 'removeAnimation', 'speed =']:
            self.assertNotIn(bad, s)
        for bound in ['visited < 2048, depth < 64', 'emitted < 64', '.prefix(8)', '[15.0, 30, 45, 60, 90, 120, 150, 180, 210]']:
            self.assertIn(bound, s)
