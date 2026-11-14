from pathlib import Path
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[2]
class FilesOptionalLogWindowTests(unittest.TestCase):
    def test_window_wraps_optional_test_and_is_uploaded(self):
        source=(ROOT/'.github/workflows/journal-open-state-ui.yml').read_text()
        self.assertLess(source.index('> files-cancel-window/start-utc.txt'), source.index('-resultBundlePath "$RUNNER_TEMP/ate-test-results/files-cancel-system-diagnostic.xcresult"'))
        self.assertLess(source.index('Retain optional Files invocation unified-log window'),source.index('Record Files cancellation acceptance boundary'))
        self.assertIn('            files-cancel-window\n',source)
        self.assertIn('--start "$start_utc" --end "$end_utc" --timezone UTC',source)
        self.assertIn('Optional test start marker missing; no covered log window claimed.',source)
        yaml.safe_load(source)
