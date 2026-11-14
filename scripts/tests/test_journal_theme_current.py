from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class JournalThemeCurrentTests(unittest.TestCase):
    def test_both_journal_owners_share_palette_without_replacing_geometry(self):
        views = (ROOT/'Ate/Views/JournalViews.swift').read_text()
        modifier = views.split('struct JournalHomeLayout: ViewModifier')[1].split('/// More')[0]
        for required in ['.scrollContentBackground(.hidden)', '.background(Theme.background)', '.foregroundStyle(Theme.foreground)', '.tint(Theme.primary)', '.listSectionSpacing(.custom(JournalHomeMetrics.sectionGap))', 'JournalHomeMetrics.bottomMargin']:
            self.assertIn(required, modifier)
        for path in ['JournalViews.swift','JournalTimelineView.swift']:
            source = (ROOT/'Ate/Views'/path).read_text()
            self.assertIn('.modifier(JournalHomeLayout())', source)
            self.assertIn('.listRowBackground(Theme.card)', source)
        self.assertIn('static let sectionGap: CGFloat = 12', views)
        insights = (ROOT/'Ate/Views/InsightsView.swift').read_text()
        self.assertIn('Theme.background.ignoresSafeArea()', insights)
