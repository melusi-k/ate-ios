from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class TabCollectionRetentionTests(unittest.TestCase):
    def test_tab_binding_uses_distinct_state_transition(self):
        root=(ROOT/'Ate/App/AteApp.swift').read_text().split('var tabSelection: Binding<AppTab>',1)[1].split('\n    }',1)[0]
        self.assertIn('store.selectTab(new)',root)
        self.assertNotIn('store.select(new)',root)
        store=(ROOT/'Ate/Store/AppStore.swift').read_text()
        self.assertIn('if t == .library { tab = t }',store)
        self.assertIn('case .library: filter.collection = nil; tab = t',store)
    def test_original_explore_native_assertions_untouched(self):
        self.assertEqual(hashlib.sha256((ROOT/'AteUITests/ExploreUITests.swift').read_bytes()).hexdigest(),'94b46cdbca8d0e61072956792061874b76f15ec06ee61942d850657d7eb5fc72')
