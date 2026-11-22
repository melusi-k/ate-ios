"""Diagnostic trigger and real subprocess outcomes, not native performance proof."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import threading
import signal
import time
ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('group28_idle', ROOT / 'scripts/group28_idle_samples.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)

class Group28SamplesTests(unittest.TestCase):
    def test_only_first_two_open_fresh_phases(self):
        w = M.PhaseWatch()
        w.line('STARTUP-TEST phase=browse-tap-start uptime=100')
        self.assertEqual(list(w.due(111)), [])
        w.line("Test Case '-[AteUITests.AteUITests test28_GroupSortAndMenus]' started.")
        w.line('STARTUP-TEST phase=browse-tap-start uptime=100')
        self.assertEqual(list(w.due(109.9)), [])
        self.assertEqual(list(w.due(110)), ['browse'])
        self.assertEqual(list(w.due(111)), [])
        w.line('STARTUP-TEST phase=browse-tap-end uptime=112')
        w.line('STARTUP-TEST phase=browse-tap-start uptime=120')
        self.assertEqual(list(w.due(130)), [])
        w.line('STARTUP-TEST phase=submenu-tap-start uptime=140')
        self.assertEqual(list(w.due(150)), ['submenu'])
        self.assertEqual(len(w.sampled), 2)
        stale = M.PhaseWatch()
        stale.active = True
        stale.line('STARTUP-TEST phase=browse-tap-start uptime=1')
        self.assertEqual(list(stale.due(32)), [])
        ended = M.PhaseWatch()
        ended.active = True
        ended.line('STARTUP-TEST phase=browse-tap-start uptime=100')
        ended.line('STARTUP-TEST phase=browse-tap-end uptime=102')
        self.assertEqual(list(ended.due(110)), [])

    def test_pid_scope_rejects_other_simulators_and_ambiguous_targets(self):
        text = '11 /x/Devices/SIM/data/Ate.app/Ate\n12 /x/Devices/OTHER/data/Ate.app/Ate\n13 /x/Devices/SIM/data/AteUITests-Runner.app/AteUITests-Runner\n14 /usr/bin/sample 11\n'
        self.assertEqual(M.targets(text, 'SIM'), {'app': [11], 'runner': [13]})
        self.assertEqual(M.targets(text + '15 /x/Devices/SIM/data/Ate.app/Ate\n', 'SIM')['app'], [11, 15])

    def test_native_status_output_and_joined_receipt_with_real_subprocess(self):
        for code in [0, 1, 65]:
            with self.subTest(code=code), tempfile.TemporaryDirectory() as tmp:
                d = Path(tmp)
                result = subprocess.run([sys.executable, str(ROOT / 'scripts/group28_idle_samples.py'), '--log', str(d/'native.log'), '--simulator', 'SIM', '--output', str(d/'samples'), '--', sys.executable, '-c', f'import sys; print("native-output"); sys.exit({code})'], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stdout, 'native-output\n')
                receipt = json.loads((d/'samples/receipt.json').read_text())
                self.assertTrue(receipt['diagnostic_only'])
                self.assertEqual(receipt['sampled_phases'], [])

    def test_exact_workflow_inverse_only_wrapper_and_artifact_path(self):
        payload = (ROOT / 'scripts/tests/group28_idle_samples_inverse.json').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), FIXTURE_SHA)
        c = json.loads(payload)
        current = (ROOT / c['path']).read_text()
        self.assertEqual(hashlib.sha256(current.encode()).hexdigest(), c['current_sha256'])
        restored = current.replace('          python3 scripts/group28_idle_samples.py --log dogfood-critical-flows.log --simulator "$SIM_ID" --output dogfood-idle-samples -- \\\n', '', 1).replace('            dogfood-idle-samples\n', '', 1)
        self.assertEqual(restored, c['old'])
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), c['parent_sha256'])

FIXTURE_SHA = '2b036a90653507ebb1b1fea1af1d8ea69bd33e0aeb71ac1c58852bdbdb4efe33'

class SampleFailureTests(unittest.TestCase):
    def test_missing_pid_and_sample_error_remain_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            with patch.object(M.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='')):
                events = M.capture('browse', 'SIM', output, threading.Event())
            self.assertEqual(len(events), 2)
            self.assertTrue(all(e['status'] == 'missing-or-ambiguous-pid' for e in events))
            ps = subprocess.CompletedProcess([], 0, stdout='11 /x/Devices/SIM/data/Ate.app/Ate\n')
            with patch.object(M.subprocess, 'run', side_effect=[ps, subprocess.TimeoutExpired('sample', 6)]):
                events = M.capture('submenu', 'SIM', output, threading.Event())
            self.assertEqual(events[-1]['status'], 'capture-error')
            self.assertNotIn('success', str(events))

class TerminationTests(unittest.TestCase):
    def test_termination_forwards_and_joins(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/group28_idle_samples.py'), '--log', str(d/'native.log'), '--simulator', 'SIM', '--output', str(d/'samples'), '--', sys.executable, '-c', 'import time; print("ready", flush=True); time.sleep(20)'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), 'ready')
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 143)
                self.assertTrue((d/'samples/receipt.json').exists())
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
