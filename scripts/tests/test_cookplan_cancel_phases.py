"""Fixed cancellation phase evidence, no repaired product behavior claim."""
from pathlib import Path
import hashlib
import json
import re
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
from cookplan_cancel_phase_delta import restore
import ui_query_samples as M

class CookPlanCancelPhaseTests(unittest.TestCase):
    def test_exact_inverse_and_mutants_fail_closed(self):
        contracts = json.loads((ROOT/'scripts/tests/cookplan_cancel_phase_inverse.json').read_text())
        for path, c in contracts.items():
            source = (ROOT/path).read_text()
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), c['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            f = c['fragments'][-1]
            for mutant in [source+'// unrelated', source.replace(f['new'], '', 1), source+f['new']]:
                with self.assertRaises(AssertionError):
                    restore(path, mutant)
            if path.endswith('.swift'):
                for token in ['await ', 'Task {', 'DispatchQueue.global(qos: .utility).async', 'continuation.resume()', 'dismiss()', 'XCTAssert', 'timeout: 10']:
                    self.assertEqual(source.count(token), old.count(token), (path, token))

    def test_flag_gate_fixed_content_and_no_new_scheduling(self):
        service = (ROOT/'Ate/Services/CookPlanNotifications.swift').read_text()
        helper = service.split('enum CookPlanCancelDiagnostic {', 1)[1]
        for token in ['#if DEBUG', 'AppConfig.isUITesting', '-qaCookPlanCancelDiagnostic', 'DispatchTime.now().uptimeNanoseconds', 'Thread.isMainThread']:
            self.assertIn(token, helper)
        for token in ['recipeID', 'reminderID', 'Date()', 'Task {', 'DispatchQueue', 'sleep', 'Timer', 'while ', 'for ', 'pendingIDs()', 'notificationSettings']:
            self.assertNotIn(token, helper)
        test = (ROOT/'AteUITests/CookPlanUITests.swift').read_text()
        self.assertEqual(test.count('-qaCookPlanCancelDiagnostic'), 1)
        self.assertEqual(test.count('cookPlanCancelQueryMark("begin")'), 1)
        self.assertEqual(test.count('cookPlanCancelQueryMark("end")'), 1)
        flags = []
        for path in (ROOT/'AteUITests').glob('*.swift'):
            if '-qaCookPlanCancelDiagnostic' in path.read_text():
                flags.append(path.name)
        self.assertEqual(flags, ['CookPlanUITests.swift'])
        self.assertIn('XCTAssertTrue(reminder.waitForNonExistence(timeout: 10), "Cancel must dismiss the saved plan sheet before reopening")', test)
        self.assertIn('XCTAssertFalse(app.buttons["cookPlan.cancelPlan"].exists)', test)

    def test_cancel_boundaries_bracket_existing_work_and_disappearance(self):
        sheet = (ROOT/'Ate/Views/CookPlanSheet.swift').read_text()
        s = sheet.split('private func cancel() {', 1)[1]
        tokens = ['handler-enter', 'busy = true', 'busy-set', 'Task { @MainActor in', 'task-enter', 'local-cancel-before', 'try store.cookPlanStore.cancel', 'local-cancel-after', 'notification-cancel-before', 'try await store.cookPlanNotifications.cancel', 'notification-cancel-after', 'busy = false', 'dismiss-before', 'dismiss()', 'dismiss-return', 'cancel-catch']
        indexes = [s.index(x) for x in tokens]
        self.assertEqual(indexes, sorted(indexes))
        self.assertIn('.onDisappear { CookPlanCancelDiagnostic.mark("sheet-disappear") }', sheet)
        service = (ROOT/'Ate/Services/CookPlanNotifications.swift').read_text()
        for tokens in [
            ['queue-register', 'queue-task-enter', 'queue-predecessor-before', '_ = try? await previous?.value', 'queue-predecessor-after', 'queue-work-before', 'try await work(token)', 'queue-work-after'],
            ['off-save-local-before', 'try store.save(plan)', 'off-save-local-after', 'let removal = enqueue', 'off-save-cleanup-registered', 'off-save-cleanup-await', 'try await removal.value', 'off-save-cleanup-return', 'off-save-cleanup-catch'],
            ['remove-before', 'await client.remove(ids)', 'remove-after', 'pending-ids-before', 'let remaining = await client.pendingIDs()', 'pending-ids-after', 'verify-failed', 'verify-passed'],
            ['utility-dispatch-before', 'DispatchQueue.global(qos: .utility).async', 'utility-enter', 'operation(ids)', 'utility-operation-return', 'continuation.resume()', 'removal-continuation-return']]:
            indexes = [service.index(x) for x in tokens]
            self.assertEqual(indexes, sorted(indexes))

    def test_cancel_watcher_fresh_once_closed_stale_and_test_end(self):
        begin = 'UI-QUERY-DIAGNOSTIC boundary=cook-plan-cancel edge=begin monotonic_ns=100000000000'
        end = 'UI-QUERY-DIAGNOSTIC boundary=cook-plan-cancel edge=end monotonic_ns=110100000000'
        w = M.QueryWatch(); w.line(begin)
        self.assertEqual(list(w.due(109.99)), [])
        self.assertEqual(list(w.due(110)), ['cook-plan-cancel'])
        self.assertEqual(list(w.due(111)), [])
        w.line(end); self.assertEqual(list(w.due(112)), [])
        stale = M.QueryWatch(); stale.line(begin)
        self.assertEqual(list(stale.due(130.01)), [])
        for suffix in ['failed (10.0 seconds).', 'passed (5.0 seconds).', 'exceeded execution time allowance']:
            w = M.QueryWatch(); w.line(begin)
            w.line("Test Case '-[AteUITests.CookPlanUITests testSavedRecipePlanWithoutReminderCanBeReopenedAndCancelled]' " + suffix)
            self.assertEqual(list(w.due(110)), [])

    def test_workflow_keeps_native_selection_pipeline_and_status(self):
        path = '.github/workflows/compile-check.yml'
        source = (ROOT/path).read_text()
        old = restore(path, source)
        for token in ['-only-testing:', '-skip-testing:', '-default-test-execution-time-allowance', '-maximum-test-execution-time-allowance', '|| status=$?', 'exit "$status"', 'stop_lifecycle', 'scripts/stream-ui-test-progress.py']:
            self.assertEqual(source.count(token), old.count(token), token)
        self.assertIn('NSUnbufferedIO=YES python3 scripts/ui_query_samples.py --log nutrition-ui-tests.log', source)
        self.assertEqual(source.count('            cook-plan-cancel-live-query\n'), 1)
        self.assertIn('CODE_SIGNING_ALLOWED=NO 2>&1 | python3 -u scripts/stream-ui-test-progress.py --selection nutrition-ui --log nutrition-ui-tests.log || status=$?', source)
