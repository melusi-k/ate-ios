"""Synthetic destination coverage must stay opt-in and exercise real destinations."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class InsightDestinationQATests(unittest.TestCase):
    def test_fixture_requires_debug_and_ui_testing_and_uses_its_own_diary_suite(self):
        fixture = (ROOT / 'Ate/App/InsightDestinationQAFixtures.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains(flag)', fixture)
        self.assertIn('UserDefaults(suiteName: name)', fixture)
        self.assertIn('let name = "ate.qa.insight-destinations"', fixture)
        self.assertNotIn('UserDefaults.standard', fixture)
        self.assertIn('guard requested else { return NutritionDiaryRepository() }', fixture)

    def test_same_fixture_repository_reaches_the_real_diary_without_reseeding_on_navigation(self):
        app = (ROOT / 'Ate/App/AteApp.swift').read_text()
        self.assertIn('nutritionDiaryRepository: InsightDestinationQAFixtures.repository()', app)
        self.assertIn('NutritionDiaryView(repository: InsightDestinationQAFixtures.repository(prepare: false))', app)
        self.assertIn('precondition(st.foodJournalRuntime == nil', app)

    def test_both_journeys_selected_and_retention_asserted_without_replacing_existing_selection(self):
        flow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        tests = (ROOT / 'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        for method in ['testSeededShoppingInsightOpensRealListAndRetainsSuggestion',
                       'testSeededDiaryInsightOpensRealDiaryAndRetainsSuggestion',
                       'testWeeklyCookingInsightShowsEvidenceAndNavigatesToTracker',
                       'testOpeningCookingHistoryKeepsInsightUntilExplicitDismissal']:
            self.assertIn('-only-testing:AteUITests/InsightsAcceptanceUITests/' + method, flow)
            self.assertIn('func ' + method + '()', tests)
        self.assertIn('returnToSeededInsight("shopping-multi-recipe")', tests)
        self.assertIn('returnToSeededInsight("nutrition-diary-coverage")', tests)

    def test_contextual_destination_has_typed_owner_and_no_missed_mount_boolean(self):
        source = (ROOT / 'Ate/Views/InsightsView.swift').read_text().split('private func openInsightDestination', 1)[1].split('private func refreshRecipeProgressInsight', 1)[0]
        self.assertIn('if !isRoot { store.trackerPath = [] }', source)
        self.assertIn('store.openInsightFoodDiary()', source)
        self.assertNotIn('store.showNutritionDiary = true', source)
        store = (ROOT / 'Ate/Store/AppStore.swift').read_text().split('func openInsightFoodDiary()', 1)[1].split('func handle(url:', 1)[0]
        self.assertIn('settingsPath = [.nutritionDiary]', store)
        self.assertLess(store.index('settingsPath = [.nutritionDiary]'), store.index('select(.settings)'))

    def test_diary_scrolls_its_owned_lazy_list_before_exact_row_assertions(self):
        source = (ROOT / 'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        journey = source.split('func testSeededDiaryInsightOpensRealDiaryAndRetainsSuggestion()', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('XCTAssertEqual(lists.count, 1', journey)
        self.assertIn('list.swipeUp()', journey)
        self.assertLess(journey.index('list.swipeUp()'), journey.index('wait(rows.firstMatch)'))
        self.assertIn('XCTAssertEqual(rows.count, 3', journey)
        self.assertIn('QA insight food 1', journey)
        self.assertIn('returnToSeededInsight("nutrition-diary-coverage")', journey)

    def test_header_journey_expands_native_minimized_bar_before_single_journal_tap(self):
        source = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        journey = source.split('func testNavigationHeadersRemainStableOnShoppingAndSettings()', 1)[1].split('\n    func ', 1)[0]
        self.assertEqual(journey.count('settingsTab.tap()'), 1)
        self.assertEqual(journey.count('tab("Journal")'), 1)
        self.assertLess(journey.index('settingsTab.tap()'), journey.index('tab("Journal")'))
        self.assertIn('XCTAssertTrue(settingsTab.isHittable', journey)
        self.assertIn('XCTAssertEqual(app.navigationBars.count, 1', journey)
        self.assertIn('XCTAssertTrue(addEntry.isHittable', journey)
        self.assertNotIn('settingsContent().swipeDown()', journey)

    def test_diary_return_expands_selected_settings_once_before_journal_navigation(self):
        source = (ROOT / 'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        journey = source.split('func testSeededDiaryInsightOpensRealDiaryAndRetainsSuggestion()', 1)[1]
        self.assertEqual(journey.count('settingsTab.tap()'), 1)
        self.assertLess(journey.index('back.tap()'), journey.index('settingsTab.tap()'))
        self.assertLess(journey.index('settingsTab.tap()'), journey.index('returnToSeededInsight('))
        self.assertIn('XCTAssertTrue(settingsTab.isHittable', journey)
        self.assertEqual(journey.count('XCTAssertTrue(settingsTab.isSelected'), 2)
        self.assertIn('XCTAssertEqual(rows.count, 3', journey)
        helper = source.split('private func returnToSeededInsight(', 1)[1].split('func testSeededShopping', 1)[0]
        self.assertEqual(helper.count('journal.tap()'), 1)
        self.assertIn('wait(journal)', helper)
        self.assertIn('Opening a destination must not dismiss unchanged evidence', helper)
