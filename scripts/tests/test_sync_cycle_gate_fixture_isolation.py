"""Actor-owned defaults belong inside the main-actor fixture body."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SyncCycleGateFixtureIsolationTests(unittest.TestCase):
    def test_default_gate_constructed_in_actor_body_not_default_argument(self):
        source = (ROOT / 'AteTests/UserDataSyncTests.swift').read_text()
        signature = source.split('private func makeFencedHarness(', 1)[1].split('throws -> FencedHarness {', 1)[0]
        self.assertIn('gate suppliedGate: SyncCycleGate? = nil', signature)
        self.assertNotIn('SyncCycleGate()', signature)
        self.assertIn('let gate = suppliedGate ?? SyncCycleGate()', source)
        self.assertIn('@MainActor\n    private func makeFencedHarness(', source)
