"""Do not trade unit coverage or strictness for workflow deduplication."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class UnitLaneRoutingTests(unittest.TestCase):
    def setUp(self):
        self.compile = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.dogfood = (ROOT / '.github/workflows/dogfood-qualification.yml').read_text()
        self.full = self.compile.split('      - name: Full exact-head unit suite', 1)[1].split('      - name: Retain full unit diagnostics', 1)[0]

    def test_exactly_one_full_unit_selection_and_no_focused_rerun(self):
        self.assertEqual(re.findall(r'-only-testing:(AteTests[^\s\\]*)', self.compile), ['AteTests'])
        self.assertNotRegex(self.dogfood, r'-only-testing:AteTests')
        self.assertIn('xcodebuild test-without-building', self.full)

    def test_all_25_previous_named_unit_assertions_are_retained(self):
        names = json.loads((ROOT / 'docs/unit-named-pass-ledger.json').read_text())
        self.assertEqual(len(names), 25)
        expected = [name.removesuffix("]' passed").replace(' ', '/') for name in names]
        reminders = ['CookPlanNotificationTests/testDeniedPermissionCannotClaimReconciledWhenOldReminderRemovalFails', 'CookPlanNotificationTests/testDeletedRecipeReminderRemovalMustVerifyBeforeOtherReminderAdds']
        deletes = ['JournalReflectionConsumerTests/testStableIdentityDeleteAfterEditVerifiesCommittedAbsenceAndPreservesSibling', 'JournalReflectionConsumerTests/testStableIdentityDeleteRejectsUncommittedWriterThenExplicitRetrySucceeds', 'JournalReflectionConsumerTests/testStableIdentityDeleteCannotRemoveUnknownKindOrMissingID']
        root_regressions = ['GeneratedTotalTimeTests/testLegacyPhotoTotalKeepsBoundedPrepGapWithoutInventingPrepNote', 'SystemCleanupCompletionTests/testImmediateVerifiedSuccessAndFailureArePreserved', 'SystemCleanupCompletionTests/testDuplicateAndLateCallbacksCannotResumeTwice', 'SystemCleanupCompletionTests/testNeverReturningServiceReleasesWaitAsUnverified', 'SystemCleanupCompletionTests/testLateSuccessAfterDeadlineStaysUnverified', 'SystemCleanupCompletionTests/testCancellationReleasesUncooperativeWaitAndIgnoresLateReply', 'SystemCleanupCompletionTests/testAlreadyCancelledWaitDoesNotStartService', 'SystemCleanupCompletionTests/testInvalidDeadlineDoesNotStartService', 'SystemCleanupCompletionTests/testCleanupMissingSpotlightCallbackReportsSurfaceWithoutDiscardingSnapshotAssertions']
        self.assertEqual((ROOT / 'scripts/full-unit-required.txt').read_text().splitlines(), expected + reminders + deletes + root_regressions)
        self.assertIn('xcrun xcresulttool get test-results tests --path', self.full)
        self.assertIn('python3 scripts/verify-full-unit-required.py full-unit-tests.json scripts/full-unit-required.txt', self.full)

    def test_full_units_reject_failures_and_zero_or_missing_count(self):
        self.assertNotIn('continue-on-error', self.full)
        self.assertIn('exit 1', self.full)
        self.assertIn('"$total" -lt 1', self.full)
        self.assertIn('"$total" =~ ^[0-9]+$', self.full)

    def test_no_new_mac_job_or_budget_increase(self):
        self.assertEqual(self.compile.count('runs-on: xcode-27'), 2)
        nutrition = self.compile.split('  build-nutrition:', 1)[1].split('  regression-suites:', 1)[0]
        self.assertIn('timeout-minutes: 45', nutrition)
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480', self.full)
        self.assertIn('timeout-minutes: 110', self.compile)
        self.assertIn('timeout-minutes: 60', self.dogfood)

    def test_nutrition_ui_diagnostics_continue_without_erasing_unit_failure(self):
        self.assertIn("- name: Nutrition diary and goals UI regressions (#179)\n        if: ${{ always() && steps.build.outcome == 'success' }}", self.compile)
        self.assertNotIn('continue-on-error', self.full)
        self.assertLess(self.compile.index('name: full-unit-diagnostics-'), self.compile.index('- name: Nutrition diary and goals UI'))
        self.assertIn('if-no-files-found: error', self.compile)

    def test_cook_ingredient_ui_guards_remain_separate(self):
        cook = self.compile.split('- name: Cook Mode ingredient sheet (UI;', 1)[1].split('- name: Require retained regression logs', 1)[0]
        self.assertNotIn('CookSessionTests', cook)
        for method in ('testCookIngredientSheetScalesChecksAndPersists', 'testCookIngredientSheetNormalTextAccessibilityAndImperial', 'testCookTimerCardNormalText'):
            self.assertIn('CookIngredientsUITests ' + method + "]' passed", cook)
        self.assertIn('-skip-testing:AteUITests/CookIngredientsUITests/testCookTimerCardLargeText', cook)

    def test_dogfood_critical_flows_remain_required_on_exact_head(self):
        self.assertIn('ref: ${{ github.event.pull_request.head.sha || github.sha }}', self.dogfood)
        for method in ('testQA1_AddFromURL_JSONLD', 'testQA1_AddFromURL_InstagramCaption', 'testQA1_AddFromURL_HiddenCaptionFallback', 'testQA2_AddFromPhoto', 'testQA3_GenerateAndEdit', 'testQA4_Save', 'testQA5_Share', 'testQA6_OpenShared', 'testQA8_Timers', 'test28_GroupSortAndMenus', 'test29_ReorderMyOrder'):
            self.assertIn('/' + method, self.dogfood)
        self.assertIn('missing named Library pass', self.dogfood)
        self.assertIn('"$total" -lt 9', self.dogfood)

    def test_sync_quarantine_is_not_a_qualification_pass(self):
        q = self.dogfood.split('- name: Diagnose quarantined Settings/account-sync', 1)[1].split('- name: Summarize qualification', 1)[0]
        self.assertIn('continue-on-error: true', q)
        self.assertIn('-only-testing:AteUITests/KeyFlowsQATests/testQA7_SyncAccount', q)
        self.assertIn('QUARANTINED / NOT A QUALIFICATION PASS', self.dogfood)

    def test_dogfood_cannot_claim_units_it_no_longer_runs(self):
        self.assertIn('Unit tests: NOT RUN HERE.', self.dogfood)
        self.assertNotIn('steps.unit_tests', self.dogfood)
        self.assertNotIn('dogfood-unit-tests.log', self.dogfood)
        self.assertIn('Qualification commit: $(git rev-parse HEAD)', self.dogfood)

    def test_existing_gate_ids_and_names_unchanged(self):
        for context in ('  build-nutrition:', '  regressions:', '  compile:', 'name: Compile qualification result'):
            self.assertIn(context, self.compile)
        self.assertIn('name: Dogfood qualification result', self.dogfood)
        self.assertIn('BUILD_NUTRITION_RESULT: ${{ needs.build-nutrition.result }}', self.compile)
        self.assertIn('[ "$BUILD_NUTRITION_RESULT" != success ]', self.compile)


if __name__ == '__main__':
    unittest.main()
