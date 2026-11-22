"""Source equivalence and real process behavior, not native capture proof."""
from pathlib import Path
import hashlib
import json
import signal
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import ui_query_samples as M
from live_query_capture_delta import restore

class LiveQueryCaptureTests(unittest.TestCase):
    def test_fresh_open_once_per_boundary(self):
        w = M.QueryWatch()
        for name in ['tracker-returned-month', 'cook-add-title']:
            mark = f'UI-QUERY-DIAGNOSTIC boundary={name} edge=begin monotonic_ns=100000000000'
            w.line(mark)
            self.assertEqual(list(w.due(109.9)), [])
            self.assertEqual(list(w.due(110)), [name])
            self.assertEqual(list(w.due(111)), [])
            w.line(mark)
            self.assertEqual(list(w.due(112)), [])
        for edge, now in [('end', 110), ('begin', 130.01)]:
            w = M.QueryWatch()
            w.line('UI-QUERY-DIAGNOSTIC boundary=cook-add-title edge=begin monotonic_ns=100000000000')
            w.line(f'UI-QUERY-DIAGNOSTIC boundary=cook-add-title edge={edge} monotonic_ns=100000000000')
            self.assertEqual(list(w.due(now)), [])
        w.line('UI-QUERY-DIAGNOSTIC boundary=other edge=begin monotonic_ns=100000000000')
        self.assertNotIn('other', w.open)

    def test_exact_simulator_service_and_executable_required(self):
        ps = '11 /x/Ate.app/Ate\n12 /x/AteUITests-Runner.app/AteUITests-Runner\n'
        service = '11 0 UIKitApplication:com.melusik.ate[abc]\n'
        self.assertEqual(M.app_pid(ps, service), 11)
        for wrong in ['', '12 0 UIKitApplication:com.melusik.ate[abc]\n', service + '13 0 UIKitApplication:com.melusik.ate[def]\n', '11 0 UIKitApplication:com.melusik.ate.UITests[abc]\n']:
            self.assertIsNone(M.app_pid(ps, wrong))

    def test_metadata_sample_stderr_timeout_and_closed_boundary(self):
        def run(command, stdout, stderr, timeout):
            if command[0] == '/bin/ps':
                stdout.write('11 /x/Ate.app/Ate\n')
            elif command[0] == 'xcrun':
                self.assertEqual(command[3], 'SIM')
                stdout.write('11 0 UIKitApplication:com.melusik.ate[abc]\n')
            else:
                self.assertEqual(command[2], '1')
                stderr.write('retained sample error\n'); stderr.flush()
                if failure:
                    raise subprocess.TimeoutExpired(command, timeout)
            return subprocess.CompletedProcess(command, 0)
        for failure in [False, True]:
            with tempfile.TemporaryDirectory() as tmp:
                d = Path(tmp)
                with patch.object(M.subprocess, 'run', side_effect=run):
                    result = M.capture('cook-add-title', 'SIM', d, threading.Event())
                self.assertEqual(result['status'], 'capture-error' if failure else 'sample-returned')
                self.assertEqual((d/'cook-add-title-sample.stderr.txt').read_text(), 'retained sample error\n')
                self.assertTrue((d/'cook-add-title-processes.stdout.txt').read_text())
                self.assertTrue((d/'cook-add-title-services.stdout.txt').read_text())
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(M.subprocess, 'run', side_effect=run):
                result = M.capture('cook-add-title', 'SIM', Path(tmp), threading.Event(), lambda: False)
            self.assertEqual(result['status'], 'boundary-closed-or-stale-before-sample')
        with tempfile.TemporaryDirectory() as tmp:
            def missing(command, stdout, stderr, timeout):
                stderr.write('metadata stderr\n')
                return subprocess.CompletedProcess(command, 0)
            with patch.object(M.subprocess, 'run', side_effect=missing):
                result = M.capture('tracker-returned-month', 'SIM', Path(tmp), threading.Event())
            self.assertEqual(result['status'], 'missing-ambiguous-or-unverified-app-pid')
            self.assertTrue((Path(tmp)/'tracker-returned-month-processes.stderr.txt').exists())

    def test_real_exit_status_output_and_joined_receipt(self):
        for code in [0, 1, 65]:
            with tempfile.TemporaryDirectory() as tmp:
                d = Path(tmp)
                result = subprocess.run([sys.executable, str(ROOT/'scripts/ui_query_samples.py'), '--log', str(d/'native.log'), '--simulator', 'SIM', '--output', str(d/'samples'), '--', sys.executable, '-c', f'import sys; print("native-output"); sys.exit({code})'], capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, code)
                self.assertEqual(result.stdout, 'native-output\n')
                self.assertEqual(json.loads((d/'samples/receipt.json').read_text())['sampled_boundaries'], [])

    def test_real_signal_forwarding_and_join(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            process = subprocess.Popen([sys.executable, str(ROOT/'scripts/ui_query_samples.py'), '--log', str(d/'native.log'), '--simulator', 'SIM', '--output', str(d/'samples'), '--', sys.executable, '-c', 'import time; print("ready", flush=True); time.sleep(20)'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), 'ready')
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=5)
                self.assertEqual(process.returncode, 143)
                self.assertTrue((d/'samples/receipt.json').exists())
            finally:
                if process.poll() is None:
                    process.kill(); process.communicate()

    def test_pinned_inverse_missing_duplicate_and_unrelated_fail_closed(self):
        contracts = json.loads((ROOT/'scripts/tests/live_query_capture_inverse.json').read_text())
        for path, c in contracts.items():
            source = (ROOT/path).read_text()
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), c['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            for mutant in [source+'// unrelated', source.replace(c['fragments'][-1]['new'], '', 1), source+c['fragments'][-1]['new']]:
                with self.assertRaises(AssertionError):
                    restore(path, mutant)
        source = (ROOT/'AteUITests/CookingTrackerEntryUITests.swift').read_text()
        block = source.split('let returnedMonthPredicate', 1)[1].split('XCTAssertFalse(next.isEnabled', 1)[0]
        self.assertEqual(block.count('element.label'), 1)
        self.assertIn('NSPredicate(format: "label == %@", currentMonth)', block)
        self.assertIn('returnedMonthPredicate.evaluate(with: ["label": label])', block)
        self.assertIn('timeout: 3)', block)
        self.assertIn('XCTAssertEqual(returnedMonthResult, .completed)', block)
        self.assertNotIn('month.label', block)
        ui = (ROOT/'AteUITests/AteUITests.swift').read_text()
        self.assertIn('wait(text("Add a recipe"))', ui)
        self.assertEqual(ui.count('cookAddTitleQueryMark("begin")'), 1)
        self.assertEqual(ui.count('cookAddTitleQueryMark("end")'), 1)
