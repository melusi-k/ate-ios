"""Pin atomic test rendezvous and deterministic native lost-wakeup replay."""
from pathlib import Path
import hashlib
import json
import unittest
from insights_atomic_read_delta import restore
ROOT = Path(__file__).resolve().parents[2]

class InsightsAtomicReadTests(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads((ROOT / 'scripts/tests/insights_atomic_read_inverse.json').read_text())
        self.source = (ROOT / self.contract['path']).read_text()

    def test_exact_inverse_preserves_all_four_ownership_bodies(self):
        old = restore(self.source)
        self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), self.contract['parent_sha256'])
        self.assertEqual(restore(old), old)
        # Everything from the original first test helper onward is byte-identical.
        anchor = '    private func summary('
        self.assertEqual(self.source[self.source.index(anchor):], old[old.index(anchor):])
        self.assertEqual(self.source.count('func test'), old.count('func test') + 2)

    def test_ready_check_and_registration_share_one_critical_section(self):
        helper = self.source.split('private final class SuspendedInsightReads<Value> {', 1)[1].split('private final class SuspendedInsightHealth:', 1)[0]
        register = helper.split('    func whenRead(', 1)[1].split('    func waitForRead(', 1)[0]
        expected = '''        let ready = lock.withLock {
            if values.count >= count { return true }
            waiters.append(Waiter(count: count, notify: notify))
            return false
        }
        if ready { notify() }'''
        self.assertIn(expected, register)
        arrival = helper.split('    func append(', 1)[1].split('    func whenRead(', 1)[0]
        self.assertIn('let ready: [() -> Void] = lock.withLock {\n            values.append(value)', arrival)
        self.assertIn('waiters.removeAll { $0.count <= count }\n            return ready\n        }\n        ready.forEach { $0() }', arrival)
        self.assertIn('var snapshot: [Value] { lock.withLock { values } }', helper)
        for forbidden in ['sleep(', 'Task {', 'DispatchQueue', 'Timer', 'wait(', 'timeout:', '@MainActor']:
            self.assertNotIn(forbidden, helper)

    def test_both_stubs_use_the_same_atomic_registration_without_early_check(self):
        health = self.source.split('private final class SuspendedInsightHealth:', 1)[1].split('@MainActor', 1)[0]
        self.assertEqual(health.count('func waitForRead(_ count: Int) async { await pending.waitForRead(count) }'), 2)
        self.assertEqual(health.count('var reads:'), 2)
        self.assertEqual(health.count('{ pending.snapshot }'), 2)
        self.assertEqual(health.count('pending.append(continuation)'), 2)
        self.assertNotIn('onRead', health)
        self.assertNotIn('if reads.count', health)

    def test_native_replay_and_critical_section_mutants_fail_closed(self):
        replay = self.source.split('func testReadRegistrationCannotLoseArrivalAfterEarlierEmptyObservation()', 1)[1].split('func testReadRegistrationNotifiesEachThresholdOnceAfterUnlocking()', 1)[0]
        tokens = ['XCTAssertTrue(pending.snapshot.isEmpty)', 'pending.append(1)', 'pending.whenRead(1)', 'XCTAssertEqual(notifications, 1)']
        offsets = [replay.index(token) for token in tokens]
        self.assertEqual(offsets, sorted(offsets))
        mutants = [
            self.source + '// unrelated',
            self.source.replace('if values.count >= count { return true }', '', 1),
            self.source.replace('let ready = lock.withLock {', 'let ready = {', 1),
            self.source.replace('waiters.removeAll { $0.count <= count }', '', 1),
            self.source.replace('pending.append(1)\n        var notifications', 'var notifications', 1),
            self.source.replace('await pending.waitForRead(count)', 'await Task.yield()', 1),
        ]
        for mutant in mutants:
            self.assertNotEqual(mutant, self.source)
            with self.assertRaises(AssertionError):
                restore(mutant)
