"""Fixed ten-stamp-only access-lost diagnostic, not an ownership repair."""
from pathlib import Path
import hashlib
import json
import unittest
from insights_accesslost_phase_delta import restore
ROOT = Path(__file__).resolve().parents[2]
class AccessLostPhaseTests(unittest.TestCase):
    def test_exact_inverse_and_only_ten_phase_lines(self):
        c = json.loads((ROOT / 'scripts/tests/insights_accesslost_phase_inverse.json').read_text())
        source = (ROOT / c['path']).read_text()
        self.assertEqual(hashlib.sha256(restore(source).encode()).hexdigest(), c['parent_sha256'])
        clean = '\n'.join(x for x in c['new'].split('\n') if 'insightAwaitPhase(' not in x)
        self.assertEqual(clean, c['old'])
        phases = [x for x in c['new'].splitlines() if 'insightAwaitPhase(' in x]
        self.assertEqual(len(phases), 10)
        for phase in ['health-one', 'prompts-one', 'waiting-task-return', 'health-two', 'empty-task-return']:
            self.assertIn('        insightAwaitPhase("accesslost-before-' + phase + '")', phases)
            self.assertIn('        insightAwaitPhase("accesslost-after-' + phase + '")', phases)
        for mutant in [source.replace(phases[0]+'\n', '', 1), source+phases[0], source+'// unrelated']:
            with self.assertRaises(AssertionError): restore(mutant)
