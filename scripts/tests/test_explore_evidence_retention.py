from pathlib import Path
import contextlib
import importlib.util
import io
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('retain_explore', ROOT / 'scripts/retain-explore-evidence.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
class ExploreEvidenceTests(unittest.TestCase):
    def test_full_log_survives_missing_bundle_and_no_tail_cutoff(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); log = root / 'source.log'
            raw = 'earliest failing method assertion\n' + 'later line\n' * 300
            log.write_text(raw)
            capture = io.StringIO()
            with contextlib.redirect_stdout(capture):
                m.retain(log, root / 'missing.xcresult', root / 'out')
            self.assertEqual((root / 'out/explore-discovery.log').read_text(), raw)
            self.assertIn('earliest failing method assertion', capture.getvalue())
            self.assertIn('EXPLORE-EVIDENCE-END explore-discovery.log', capture.getvalue())
            self.assertIn('EXPLORE-XCRESULT-MISSING', capture.getvalue())
    def test_console_png_and_extractor_failure_are_visible(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); result = root / 'result'; result.mkdir(); out = root / 'out'
            def run(args, **kw):
                from subprocess import CompletedProcess
                if 'attachments' in args:
                    p = out / 'attachments'; p.mkdir(); (p / 'failure.png').write_bytes(b'pixel evidence')
                return CompletedProcess(args, 1, b'{"failure":"line107"}', b'extractor warning')
            capture = io.StringIO()
            with patch.object(m.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(capture):
                m.retain(root / 'missing.log', result, out)
            self.assertIn('EXPLORE-EXTRACT summary exit=1', capture.getvalue())
            self.assertIn('EXPLORE-EVIDENCE-END attachments/failure.png', capture.getvalue())
            self.assertTrue((out / 'test-summary.stderr.txt').is_file())
    def test_independent_upload_precedes_remaining_tests_and_big_upload(self):
        s = (ROOT / '.github/workflows/compile-check.yml').read_text()
        a = s.index('name: Upload small independent Explore evidence')
        self.assertLess(a, s.index('name: Expandable recipe-detail'))
        self.assertIn('always()', s[a:a+180])
        self.assertIn('retention-days: 7', s[a:a+600])
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', s)
