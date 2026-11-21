"""Dogfood console visibility only. No native stability or causal proof."""
from pathlib import Path
import hashlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
OLD = 'CODE_SIGNING_ALLOWED=NO > dogfood-critical-flows.log 2>&1'
ORIGINAL_SHA = 'e96f9209f21dc089bda4f99a6f048be38388eb9657152312f0c0d39ad66e654b'
NEW = 'CODE_SIGNING_ALLOWED=NO 2>&1 | python3 -u scripts/stream-ui-test-progress.py --selection dogfood-critical-flows --log dogfood-critical-flows.log'


class DogfoodProgressTests(unittest.TestCase):
    def test_exact_workflow_inverse_preserves_all_selection_and_failure_contracts(self):
        text = (ROOT / '.github/workflows/dogfood-qualification.yml').read_text()
        self.assertEqual(text.count(NEW), 1)
        self.assertNotIn(OLD, text)
        original = text.replace(NEW, OLD, 1)
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), ORIGINAL_SHA)
        self.assertIn('set -o pipefail', text)
        self.assertIn('timeout-minutes: 30', text)
        self.assertIn('timeout-minutes: 60', text)
        self.assertIn('if: always()', text)
        self.assertIn('dogfood-critical-flows.log', text)

    def test_exact_pipeline_lossless_failed_producer_remains_red(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'dogfood-critical-flows.log'
            producer = Path(directory) / 'producer.py'
            raw = b"Build preparation before any native test\nTest Case '-[Class testMenu]' started.\nUI-RED journey=test seq=1 BEGIN step=menu\npartial\xff"
            producer.write_text('import sys\nsys.stdout.buffer.write(' + repr(raw) + ')\nsys.stdout.flush()\nsys.exit(7)\n')
            # Static filenames under a generated temp directory, no external text in shell.
            command = f'set -o pipefail; {sys.executable} {producer} 2>&1 | {sys.executable} -u scripts/stream-ui-test-progress.py --selection dogfood-critical-flows --log {target}'
            result = subprocess.run(['bash', '-c', command], cwd=ROOT, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(target.read_bytes(), raw)
            output = result.stdout.decode()
            self.assertIn('stream-open-no-native-test-observed-yet', output)
            self.assertIn('selection=dogfood-critical-flows', output)
            self.assertIn('active=-[Class testMenu]', output)
            self.assertIn('BEGIN step=menu', output)
            self.assertIn('stream-closed-not-a-pass', output)
            self.assertNotIn('event=passed', output)


if __name__ == '__main__':
    unittest.main()
