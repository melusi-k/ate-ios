"""Guard the timer-alerts relay non-blocking delta, not native qualification."""
from pathlib import Path
import hashlib
import re
import unittest
from timer_alerts_relay_delta import contract, restore
ROOT = Path(__file__).resolve().parents[2]

class TimerAlertsRelayDeltaTests(unittest.TestCase):
    def test_exact_inverse_and_all_pins(self):
        for path, entry in contract()['files'].items():
            source = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), entry['current_sha256'])
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), entry['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            self.assertEqual(restore(path, source.encode()), old.encode())
            for mutant in [source + '// unrelated', source[:-1]]:
                with self.assertRaises(AssertionError): restore(path, mutant)

    def test_five_native_relay_cases_remain_mandatory(self):
        path = 'scripts/full-unit-required.txt'; source = (ROOT / path).read_text(); parent = restore(path, source)
        required = contract()['required_native']
        self.assertEqual(source, parent + '\n'.join(required) + '\n')
        self.assertEqual(len(source.splitlines()), len(set(source.splitlines())))
        native = (ROOT / 'AteTests/TimerAlertsRelayTests.swift').read_text()
        methods = re.findall(r'    func (test\w+)\(', native)
        self.assertEqual(['TimerAlertsRelayTests/' + n for n in methods], required)
        self.assertEqual(len(methods), 12)
        for token in ['110s stall inside TimerAlerts.schedule as a whole', 'hypothesis']:
            self.assertIn(token, native)
