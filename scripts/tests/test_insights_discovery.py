"""Source contracts complement native behavior and device acceptance, not replace them."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class InsightsDiscoveryContracts(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'Ate/Views/InsightsView.swift').read_text()
        self.discovery = (ROOT / 'Ate/Logic/RecipeDiscovery.swift').read_text()
        self.destination = (ROOT / 'Ate/Views/SuggestedNewRecipesView.swift').read_text()

    def test_confidence_evidence_stay_internal_and_lifecycle_controls_are_explicit(self):
        card = self.view.split('private var recipeProgressCard:', 1)[1].split('private func markRecipeInsightSeen', 1)[0]
        self.assertNotIn('Text(candidate.insight.evidence', card)
        self.assertNotIn('Text("Evidence:', card)
        self.assertIn('Button("Done") { resolveRecipeInsight(candidate) }', card)
        self.assertIn('.accessibilityLabel("Remind me later")', card)
        self.assertIn('.accessibilityLabel("Dismiss")', card)
        route = self.view.split('private func openInsightDestination', 1)[1].split('private func refreshRecipeProgressInsight', 1)[0]
        self.assertIn('candidate.id != "recipe-duplicates"', route)
        self.assertIn('showingRecipeDiscovery = true\n            return', route)
        self.assertNotIn('dismissRecipeInsight', route)
        self.assertNotIn('resolveRecipeInsight', route)

    def test_recommendation_replaces_both_collection_placeholders(self):
        for source in [self.view, (ROOT / 'Ate/Insights/InsightCandidateEngine.swift').read_text()]:
            self.assertNotIn('Your recipe collection is taking shape', source)
            self.assertIn('Explore a new recipe inspired by the dishes you have saved.', source)

    def test_generation_is_real_on_device_no_demo_and_no_automatic_save(self):
        self.assertIn('store.backend is OnDeviceBackend && OnDeviceBackend.isModelAvailable', self.destination)
        self.assertIn('store.backend.parseRecipe($0)', self.destination)
        self.assertIn('result.source == .appleIntelligence', self.discovery)
        self.assertNotIn('MockBackend', self.destination)
        request = self.discovery.split('func request(', 1)[1].split('@discardableResult func save', 1)[0]
        self.assertIn('ParseRequest(mode: .prompt, text: prompt)', request)
        self.assertNotIn('store.add(', request)
        self.assertNotIn('DraftStore', request)
        self.assertIn('clearPendingDraft: false', self.destination)
        self.assertIn('store.recipe(recipe.id) == RecipeLogic.normalize(recipe)', self.destination)

    def test_suggestions_use_bound_sources_and_recheck_before_display_and_save(self):
        for source in ['store.cookJournalOutbox.load()', 'store.journalStore.readEntries()',
                       'store.journalCookingHistory.readEvents()']:
            self.assertIn(source, self.discovery)
        self.assertNotIn('CookingHistory.shared', self.discovery)
        self.assertIn('snapshots.filter { $0.cookedDayKey != nil }', self.discovery)
        self.assertGreaterEqual(self.discovery.count('RecipeDiscovery.excludes(card, context: current'), 2)
        self.assertIn('current.owner == input.owner', self.discovery)
        self.assertIn('current.owner == owner', self.discovery)

    def test_normal_size_visual_journey_and_terminal_deadline_are_present(self):
        self.assertIn('card("Recipe & cooking insights", subduedHeader: true)', self.view)
        self.assertIn('spacing: subduedHeader ? 18 : 10', self.view)
        self.assertIn('AteFont.body(17, .bold)', self.view)
        self.assertIn('subduedHeader ? Theme.mutedForeground : Theme.foreground', self.view)
        self.assertIn('timeoutNanoseconds: UInt64 = 60_000_000_000', self.discovery)
        self.assertIn('cancel() // revoke the publication token', self.discovery)
        tests = (ROOT / 'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        self.assertIn('testExploreOpensNewSuggestionsNotLibraryAndUnavailableAIIsHonest', tests)
        self.assertIn('insights-normal-quiet-header-primary-title-controls', tests)
        self.assertIn('insights-new-suggestions-unavailable-no-demo', tests)

    def test_month_summary_is_two_body_size_high_contrast_items_with_real_padding(self):
        tracker = (ROOT / 'Ate/Views/CookingTrackerView.swift').read_text()
        row = tracker.split('let monthSummary = CookingMonthSummary.make', 1)[1].split('LazyVGrid', 1)[0]
        self.assertIn('Text(monthSummary.daysText)', row)
        self.assertIn('Text(monthSummary.recipesText)', row)
        self.assertIn('AteFont.body(16, .semibold)', row)
        self.assertIn('Theme.foreground', row)
        self.assertIn('Theme.secondaryForeground', row)
        self.assertIn('.padding(.vertical, 12)', row)
        summary = (ROOT / 'Ate/Logic/CookingMonthSummary.swift').read_text()
        self.assertNotIn('distinct ', summary.split('var daysText:', 1)[1])
        tests = (ROOT / 'AteTests/CookingMonthSummaryTests.swift').read_text()
        self.assertIn('testSummaryItemsPluralizeIndependentlyWithoutChangingValues', tests)
