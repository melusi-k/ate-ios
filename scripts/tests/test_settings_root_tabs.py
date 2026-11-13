"""Static policy check only; native visibility/pixels must still be qualified."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SettingsRootTabsTests(unittest.TestCase):
    def test_settings_never_minimizes_other_roots_keep_scroll_behavior(self):
        source = (ROOT / 'Ate/App/AteApp.swift').read_text()
        self.assertEqual(source.count('.tabBarMinimizeBehavior('), 1)
        self.assertIn('.tabBarMinimizeBehavior(store.tab == .settings ? .never : .onScrollDown)', source)
        self.assertIn('Tab("Journal", systemImage: "book.closed", value: AppTab.tracker)', source)
        self.assertIn('NavigationStack(path: $store.settingsPath)', source)
