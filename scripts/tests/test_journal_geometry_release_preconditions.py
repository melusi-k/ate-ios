from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class JournalGeometryReleasePreconditions(unittest.TestCase):
    def test_actual_root_route_cards_have_distinct_sections(self):
        root = (ROOT / 'Ate/Views/JournalTimelineView.swift').read_text()
        self.assertIn('}.accessibilityIdentifier("journal.insightsHistory")\n                }\n                Section {\n                    NavigationLink(value: Route.nutritionDiary)', root)
        self.assertIn('.modifier(JournalHomeLayout())', root)
        test = (ROOT / 'AteUITests/CookReflectionUITests.swift').read_text().split('func testKeepLaterReopensSameDraftAcrossRotation()',1)[1].split('func testOptionalCookReflectionUsesNavigationHostAfterFinish',1)[0]
        self.assertNotIn('journal.timelineLink', test)
        self.assertIn('app.cells.containing(.any, identifier: "journal.meals")', test)
        self.assertIn('for cell in [notesCell, insightsCell, mealsCell, reflectionCell] { wait(cell) }', test)
        self.assertIn('for gap in gaps { XCTAssertEqual(gap, 12, accuracy: 2', test)
        self.assertIn('XCTAssertEqual(note.value as? String, retained)', test)

    def test_release_history_fixture_is_explicit_debug_uitest_only(self):
        fixture = (ROOT / 'Ate/App/ProductReleaseNotesQAFixture.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('guard isUITesting, arguments.contains("-qaReleaseHistory445") else { return actual }', fixture)
        view = (ROOT / 'Ate/Views/ProductUpdatesViews.swift').read_text()
        self.assertIn('#else\n        return actual\n#endif', view)
        self.assertIn('visibleReleases(build: catalogBuildNumber', view)
        self.assertIn('publishedBuildReleases(build: catalogBuildNumber', view)
        test = (ROOT / 'AteUITests/InsightsPresentationUITests.swift').read_text()
        self.assertIn('launch(["-qaReleaseHistory445", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])', test)
