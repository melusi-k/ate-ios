"""Fixed-count await evidence cannot change the original ownership contract."""
from pathlib import Path
import hashlib
import json
import unittest
from insights_accesslost_phase_delta import restore as restore_accesslost
ROOT = Path(__file__).resolve().parents[2]

class InsightsAwaitPhaseTests(unittest.TestCase):
    def test_exact_inverse_preserves_original_test_and_helpers(self):
        c = json.loads((ROOT / 'scripts/tests/insights_await_phase_inverse.json').read_text())
        source = restore_accesslost((ROOT / 'AteTests/InsightsRefreshOwnershipTests.swift').read_text())
        self.assertEqual(source.count(c['new']), 1)
        self.assertTrue(source.endswith(c['helper']))
        restored = source[:-len(c['helper'])].replace(c['new'], c['old'], 1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), c['parent_sha256'])
        self.assertEqual(c['new'].count('insightAwaitPhase('), 12)
        for forbidden in ['Task {', 'DispatchQueue', 'wait(', 'sleep(', 'Timer', '@MainActor']:
            self.assertNotIn(forbidden, c['helper'])
        self.assertIn('FileHandle.standardOutput.write', c['helper'])
        self.assertEqual(c['new'].count('await '), c['old'].count('await '))
