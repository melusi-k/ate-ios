"""A single fresh wait sample cannot change native status or test contract."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import cook_entry_sample as M

class CookEntrySampleTests(unittest.TestCase):
    def test_only_one_fresh_named_open_wait(self):
        w = M.EntryWatch()
        mark = 'COOK-REMOVAL-PHASE phase=before-entry-wait monotonic_ns=100000000000 main_thread=true'
        w.line(mark)
        self.assertFalse(w.due(100.5))
        w.line("Test Case '-[AteTests.CookPlanNotificationTests testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly]' started.")
        w.line(mark)
        self.assertFalse(w.due(100.24))
        self.assertTrue(w.due(100.25))
        self.assertFalse(w.due(100.6))
        stale = M.EntryWatch()
        stale.active = True
        stale.line(mark)
        self.assertFalse(stale.due(101.26))
        ended = M.EntryWatch()
        ended.active = True
        ended.line(mark)
        ended.line('COOK-REMOVAL-PHASE phase=entry-wait-return monotonic_ns=100100000000 main_thread=true')
        self.assertFalse(ended.due(100.5))

    def test_missing_pid_and_sample_failure_retained(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            with patch.object(M.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='')):
                self.assertEqual(M.capture('SIM', output)['status'], 'missing-or-ambiguous-pid')
            ps = subprocess.CompletedProcess([], 0, stdout='11 /x/Devices/SIM/data/Ate.app/Ate\n')
            with patch.object(M.subprocess, 'run', side_effect=[ps, subprocess.TimeoutExpired('sample', 3)]):
                self.assertEqual(M.capture('SIM', output)['status'], 'capture-error')

    def test_real_child_output_exit_and_receipt(self):
        for code in [0, 1, 65]:
            with tempfile.TemporaryDirectory() as tmp:
                d = Path(tmp)
                result = subprocess.run([sys.executable, str(ROOT/'scripts/cook_entry_sample.py'), '--log', str(d/'unit.log'), '--simulator', 'SIM', '--output', str(d/'samples'), '--', sys.executable, '-c', f'import sys; print("native-output"); sys.exit({code})'], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stdout, 'native-output\n')
                self.assertFalse(json.loads((d/'samples/receipt.json').read_text())['sample_requested'])

    def test_exact_inverse_only_command_prefix_artifact_and_observer_injection(self):
        payload = (ROOT/'scripts/tests/cook_entry_sample_inverse.json').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), FIXTURE_SHA)
        c = json.loads(payload)
        for item in c.values():
            self.assertEqual((ROOT/item['path']).read_text(), item['new'])
        wf = c['workflow']['new'].replace('          python3 scripts/cook_entry_sample.py --log full-unit-tests.log --simulator "$SIM_ID" --output cook-entry-sample -- \\\n', '', 1).replace('            cook-entry-sample\n', '', 1)
        self.assertEqual(wf, c['workflow']['old'])
        wrapper = c['wrapper']['new'].replace('def main(observer=observe):', 'def main():', 1).replace('threading.Thread(target=observer,', 'threading.Thread(target=observe,', 1)
        self.assertEqual(wrapper, c['wrapper']['old'])
        self.assertEqual(hashlib.sha256((ROOT/'AteTests/CookPlanNotificationTests.swift').read_bytes()).hexdigest(), TEST_SHA)

FIXTURE_SHA = '9012e77dcf40c51fd362d968023b9a0073b571a7625bbf67b5e3ecfebd621ab5'
TEST_SHA = 'f74ce8876ea4962b52ee7b1da0649868c2c3b5bf184e2b30c5b6963ea438f934'

class CookEntryInverseMutants(unittest.TestCase):
    def test_missing_duplicate_unrelated_and_selection_mutants_fail(self):
        from cook_entry_sample_delta import restore
        c = json.loads((ROOT/'scripts/tests/cook_entry_sample_inverse.json').read_text())['workflow']
        self.assertEqual(restore(c['path'], c['new']), c['old'])
        for mutant in [c['new']+'// unrelated', c['new'].replace('cook-entry-sample\n', '', 1), c['new'].replace('-only-testing:AteTests', '-only-testing:AteTests/one', 1)]:
            with self.assertRaises(AssertionError): restore(c['path'], mutant)
