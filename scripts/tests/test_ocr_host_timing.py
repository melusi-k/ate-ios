import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/capture-ocr-host-timing.py'
spec = importlib.util.spec_from_file_location('ocr_host_timing', SCRIPT)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)

PS = '''101 1 0:02.50 01:10 Thu Nov 19 09:40:00 2026 /private/path/Ate
202 1 0:01.25 00:30 Thu Nov 19 09:40:40 2026 /System/Library/XPCServices/VisionService
303 1 0:01.00 00:40 Thu Nov 19 09:40:30 2026 /private/secret-browser
'''


class OCRHostTimingTests(unittest.TestCase):
    def test_mac_ps_durations_and_basename_only_filter(self):
        self.assertEqual(host.duration_seconds('1-02:03:04.50'), 93784.5)
        self.assertEqual(host.duration_seconds('03:04.50'), 184.5)
        rows = host.parse_processes(PS + 'malformed data\n')
        self.assertEqual([p['name'] for p in rows], ['Ate', 'VisionService'])
        self.assertEqual(rows[1]['category'], 'vision_related')
        self.assertNotIn('/private', json.dumps(rows))
        self.assertNotIn('secret-browser', json.dumps(rows))
        self.assertEqual(rows[0]['os_start_local'], 'Thu Nov 19 09:40:00 2026')

    def test_wall_cpu_delta_start_visibility_load_and_pid_reuse(self):
        run = Mock(return_value=subprocess.CompletedProcess([], 0, PS, ''))
        row, state = host.sample({}, 100, 90, run, lambda: (1, 2, 3))
        self.assertEqual(row['collector_wall_seconds'], 10)
        self.assertEqual(row['load_average_1_5_15'], [1, 2, 3])
        self.assertTrue(row['vision_related_visible'])
        self.assertTrue(row['processes'][0]['first_observed'])
        run.return_value.stdout = PS.replace('0:02.50', '0:03.50')
        row, state = host.sample(state, 102, 90, run, lambda: (4, 5, 6))
        self.assertEqual(row['processes'][0]['cpu_delta_seconds'], 1)
        self.assertEqual(row['processes'][0]['sample_wall_seconds'], 2)
        self.assertEqual(row['processes'][0]['cpu_percent_of_one_core'], 50)
        run.return_value.stdout = PS.replace('09:40:00', '09:41:00')
        row, _ = host.sample(state, 104, 90, run, lambda: (1, 2, 3))
        self.assertTrue(row['processes'][0]['first_observed'])
        self.assertNotIn('cpu_delta_seconds', row['processes'][0])
        self.assertEqual(run.call_args.kwargs['timeout'], 2)
        self.assertNotIn('args=', ' '.join(run.call_args.args[0]))

    def test_missing_services_and_permission_or_timeout_are_explicit_not_fake_zeros(self):
        run = Mock(return_value=subprocess.CompletedProcess([], 0, '', ''))
        row, _ = host.sample({}, 1, 0, run, lambda: (1, 2, 3))
        self.assertFalse(row['vision_related_visible'])
        for error in [OSError('private detail'), subprocess.TimeoutExpired('private', 2),
                      subprocess.CalledProcessError(1, 'private', stderr='private')]:
            run.side_effect = error
            row, _ = host.sample({}, 1, 0, run, lambda: (1, 2, 3))
            self.assertIn('process_error', row)
            self.assertNotIn('private', json.dumps(row))

    def test_real_collector_signal_exits_and_flushes_with_a_hard_duration_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'timing.jsonl'
            proc = subprocess.Popen([sys.executable, str(SCRIPT), '--output', str(path)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                until = time.monotonic() + 3
                while time.monotonic() < until:
                    if path.exists() and 'sample' in path.read_text():
                        break
                    time.sleep(0.02)
                proc.terminate()
                stdout, stderr = proc.communicate(timeout=4)
                self.assertEqual(proc.returncode, 0, stderr)
                rows = [json.loads(line) for line in path.read_text().splitlines()]
                self.assertEqual(rows[0]['kind'], 'header')
                self.assertEqual(rows[0]['max_seconds'], 2700)
                self.assertEqual(rows[0]['interval_seconds'], 2)
                self.assertEqual(rows[-1]['kind'], 'end')
                self.assertEqual(rows[-1]['reason'], 'signal')
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.communicate(timeout=4)

    def test_workflow_preserves_native_block_and_gate_exit_on_success_and_failure(self):
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        steps = yaml.safe_load(source)['jobs']['build-nutrition']['steps']
        full = next(s['run'] for s in steps if s.get('id') == 'unit_tests')
        start = full.index('set -o pipefail\n') + len('set -o pipefail\n')
        end = full.index('echo "Full unit suite source:')
        added = full[start:end]
        self.assertIn('native_status=$?', added)
        self.assertIn('exit "$native_status"', added)
        # Strip exactly the telemetry envelope, then compare a frozen whole gate.
        import hashlib
        original = full[:start] + full[end:]
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), 'd03f7dc0336556c463a4d555b3a337ff1be59ebe293eae0c9aec7c3cbff7bbc8')
        self.assertIn('ocr-host-timing.jsonl', source)
        self.assertIn('ocr-host-timing-status.log', source)
        with tempfile.TemporaryDirectory() as directory:
            # Replace only the collector launch in this shell fixture, never the gate.
            envelope = added.replace('python3 scripts/capture-ocr-host-timing.py --output ocr-host-timing.jsonl > ocr-host-timing-status.log 2>&1 &', 'sleep 60 &')
            for status in (0, 1, 65):
                result = subprocess.run(['bash', '-c', envelope + '\nexit ' + str(status)], cwd=directory,
                                        capture_output=True, text=True, timeout=4)
                self.assertEqual(result.returncode, status)

    def test_exact_inverse_rejects_missing_changed_or_duplicate_telemetry(self):
        from ocr_host_timing_inverse import restore, ENVELOPE, ARTIFACTS
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        for block in (ENVELOPE, ARTIFACTS):
            for mutant in (source.replace(block, '', 1), source + block, source.replace(block, block.replace('ocr-host', 'wrong-host'), 1)):
                with self.assertRaises(AssertionError):
                    restore('source:.github/workflows/compile-check.yml', mutant)
