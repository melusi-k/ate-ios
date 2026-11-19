"""Wiring guards only. These are not Swift or notification-daemon acceptance."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

class TimerNotificationSourceTests(unittest.TestCase):
    def test_real_system_calls_are_worker_dependencies_not_caller_operations(self):
        source = (ROOT / 'Ate/Services/TimerAlerts.swift').read_text()
        self.assertIn('private static let worker = TimerNotificationWorker(', source)
        self.assertIn('UNUserNotificationCenter.current().removePendingNotificationRequests', source)
        self.assertIn('UNUserNotificationCenter.current().add(request) { _ in done() }', source)
        self.assertIn('center.removeAllPendingNotificationRequests()', source)
        self.assertIn('center.removeAllDeliveredNotifications()', source)
        self.assertIn('done(pending.isEmpty && delivered.isEmpty)', source)
        methods = source.split('    static func schedule(', 1)[1]
        self.assertNotIn('UNUserNotificationCenter.current()', methods)
        self.assertIn('worker.cancel(identifier: "ate.timer." + id)', methods)
        self.assertIn('await worker.removeAllAndVerify()', methods)

    def test_deadline_payload_and_disabled_alert_cancellation_preserved(self):
        source = (ROOT / 'Ate/Services/TimerAlerts.swift').read_text()
        self.assertIn('guard prefs.stepAlerts else { worker.cancel(identifier: identifier); return }', source)
        self.assertIn('let identifier = "ate.timer." + id', source)
        self.assertIn('content.title = "Step \\(step) is done"', source)
        self.assertIn('content.body = recipeTitle', source)
        self.assertIn('let interval = max(1, end.timeIntervalSinceNow)', source)
        self.assertIn('UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)', source)
        self.assertIn('.milliseconds(300)', source)

    def test_real_worker_serializes_cancel_add_completion_and_clear_barrier(self):
        source = (ROOT / 'Ate/Services/TimerNotificationWorker.swift').read_text()
        self.assertIn('DispatchQueue(label: "ate.timer-notifications"', source)
        self.assertIn('self.remove(identifier)\n            guard let request else { done(); return }\n            self.add(request(), done)', source)
        self.assertIn('guard running == nil, !pending.isEmpty else { return }', source)
        self.assertIn('guard self.running == token else { return }', source)
        self.assertNotIn('DispatchQueue.main', source)
        self.assertNotIn('writerBoundary.withEffect', source)
        self.assertNotIn('isUITesting', source)

    def test_native_blocked_service_regressions_are_required_not_rerun_or_skipped(self):
        source = (ROOT / 'AteTests/TimerNotificationWorkerTests.swift').read_text()
        required = (ROOT / 'scripts/full-unit-required.txt').read_text().splitlines()
        names = re.findall(r'    func (test\w+)\(', source)
        self.assertEqual(len(names), 3)
        for name in names:
            self.assertIn('TimerNotificationWorkerTests/' + name, required)
        self.assertIn('gate.wait()', source)
        self.assertIn('XCTAssertFalse(Thread.isMainThread)', source)
        self.assertNotIn('XCTSkip', source)
        self.assertNotIn('executionTimeAllowance', source)
