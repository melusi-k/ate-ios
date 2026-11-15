from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]
class InsightsAtomicHandshakeTests(unittest.TestCase):
    def test_original_ownership_assertions_and_actions_unchanged(self):
        source=(ROOT/'AteTests/InsightsRefreshOwnershipTests.swift').read_text()
        original=source.split('    private func summary(_ scenario: String)',1)[1]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(),'271c6493e0b08012a472b7383b61e723db0e4784f2d90921c851c63499611965')
    def test_no_single_callback_check_register_race(self):
        source=(ROOT/'AteTests/InsightsRefreshOwnershipTests.swift').read_text()
        self.assertNotIn('onRead',source)
        self.assertIn('waiters.append((count, continuation))',source)
        self.assertIn('if continuations.count >= count { return true }',source)
        self.assertIn('for waiter in ready { waiter.resume() }',source)
        self.assertIn('private let lock = NSLock()',source)
