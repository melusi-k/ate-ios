"""Source-routing checks only. These do not qualify Dynamic Island/widget pixels."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WidgetDeviceRegressionTests(unittest.TestCase):
    def test_expanded_timer_has_single_line_and_title_no_longer_competes_in_center(self):
        source = (ROOT / 'AteWidgets/AteWidgets.swift').read_text()
        island = source.split('} dynamicIsland: { context in', 1)[1]
        trailing = island.split('DynamicIslandExpandedRegion(.trailing)', 1)[1].split('DynamicIslandExpandedRegion(.bottom)', 1)[0]
        self.assertIn('.lineLimit(1)', trailing)
        self.assertIn('.fixedSize(horizontal: true, vertical: false)', trailing)
        self.assertIn('.frame(minWidth: 76', trailing)
        self.assertNotIn('DynamicIslandExpandedRegion(.center)', island)
        self.assertIn('Text(context.attributes.recipeTitle).font(.headline).lineLimit(2)', island)

    def test_cream_cooking_widget_has_explicit_brown_empty_and_status_text(self):
        source = (ROOT / 'AteWidgets/HomeWidgets.swift').read_text()
        cooking = source.split('private struct CookingWidgetView', 1)[1].split('// MARK: Tonight', 1)[0]
        self.assertNotIn('.foregroundStyle(.secondary)', cooking)
        self.assertIn('foreground: WTheme.brown', cooking)
        self.assertIn('WidgetDataMessage.unavailable(groupAvailable: entry.groupAvailable)', cooking)
        self.assertNotIn('Open ate to set up this widget', source)

    def test_explicit_refresh_bypasses_unchanged_snapshot_cache(self):
        source = (ROOT / 'SharedWidgets/WidgetShared.swift').read_text()
        self.assertIn('if let old = lastPublished, !force', source)
        self.assertIn('guard !changed.isEmpty else { return false }', source)
        bridge = (ROOT / 'Ate/Services/WidgetBridge.swift').read_text()
        self.assertIn('publisher.publish(snap, force: force, reload: WidgetKinds.reload)', bridge)
        self.assertNotIn('WidgetKinds.reloadAll()', (ROOT / 'Ate/Views/BetaTestingView.swift').read_text())
        self.assertIn('WidgetBridge.publishNow(store, force: true)', (ROOT / 'Ate/Views/BetaTestingView.swift').read_text())
