"""Deterministic entry gate: scheduler latency cannot fail or weaken the contract."""
from pathlib import Path
import hashlib
import re
import unittest
from cookplan_removal_entry_gate_delta import restore as restore_entry_gate

ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'AteTests/CookPlanNotificationTests.swift'
FN_START = '    func testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly() async {'
FN_END = '\n\n    func testEmptyRemovalDoesNotContactSystem'


class CookRemovalEntryGateTests(unittest.TestCase):
    def body(self):
        text = (ROOT / SOURCE).read_text()
        return text[text.index(FN_START):text.index(FN_END)]

    def test_entry_wait_has_no_wall_clock_bound_or_retry(self):
        body = self.body()
        self.assertIn('await entered.waitForEntry()', body)
        self.assertNotIn('expectation(', body)
        self.assertNotIn('fulfillment(of:', body)
        self.assertNotIn('timeout:', body)
        self.assertNotIn('asyncAfter', body)
        self.assertNotIn('retry', body.lower())

    def test_every_semantic_assertion_and_phase_is_retained(self):
        body = self.body()
        self.assertIn('entered.signalEntry()', body)
        self.assertIn('release.wait()', body)
        self.assertIn('release.signal()', body)
        self.assertIn('XCTAssertFalse(Thread.isMainThread, "Blocking OS removal must not run on Main")', body)
        self.assertIn('XCTAssertEqual(ids, ["cook-r1"], "Removal must preserve the requested identities")', body)
        self.assertIn('XCTAssertFalse(returned, "Ordered cleanup cannot report completion before OS removal returns")', body)
        self.assertIn('XCTAssertTrue(returned)', body)
        text = (ROOT / SOURCE).read_text()
        self.assertEqual(text.count('cookRemovalDiagnostic("'), 11)
        for phase in ['test-entry', 'main-task-entry', 'utility-callback-entry', 'before-entry-fulfill',
                      'after-entry-fulfill', 'utility-released', 'removal-await-return', 'before-entry-wait',
                      'entry-wait-return', 'before-release', 'test-completion']:
            self.assertIn(f'cookRemovalDiagnostic("{phase}")', text)

    def test_gate_signals_from_the_callback_and_resumes_exactly_once(self):
        text = (ROOT / SOURCE).read_text()
        gate = text[text.index('// Deterministic entry gate:'):]
        gate = gate[:gate.index('// Diagnostic output only:')]
        self.assertIn('private final class CookRemovalEntryGate: @unchecked Sendable {', gate)
        self.assertIn('CheckedContinuation<Void, Never>?', gate)
        self.assertEqual(gate.count('.resume()'), 2)
        self.assertIn('waiter = nil', gate)
        self.assertNotIn('DispatchQueue', gate)
        self.assertNotIn('Task {', gate)

    def test_exact_inverse_restores_the_historical_wall_clock_version(self):
        raw = (ROOT / SOURCE).read_bytes()
        restored = restore_entry_gate(SOURCE, raw)
        self.assertEqual(hashlib.sha256(restored).hexdigest(), 'f74ce8876ea4962b52ee7b1da0649868c2c3b5bf184e2b30c5b6963ea438f934')
        original = restored.decode().split('// Diagnostic output only: monotonic correlation, no scheduling or synchronization.')[0]
        original = re.sub(r'^ +cookRemovalDiagnostic\("[a-z-]+"\)\n', '', original, flags=re.M).rstrip() + '\n'
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), 'e8e42897e24abdbaf061c1b117df751de5443522663d51b8c0ea2027acc7596f')
        self.assertIn('await fulfillment(of: [started], timeout: 2)', restored.decode())
