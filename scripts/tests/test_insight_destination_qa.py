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
