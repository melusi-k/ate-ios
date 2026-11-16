"""Post-run mirror behavior and exact native-test preservation, not native acceptance."""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import yaml
from journal_snapshot_mirror_delta import restore, NEW, NEW_COMMENT
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('journal_mirror', ROOT / 'scripts/mirror-journal-snapshots.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class JournalSnapshotMirrorTests(unittest.TestCase):
    def test_lossless_postrun_mirror_never_prints_pixels_to_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = Path(directory)
            payload = b'\x89PNG\r\n\x1a\n' + bytes(range(256)) * 48
            (raw / 'shot.png').write_bytes(payload)
            (raw / 'manifest.json').write_text(json.dumps([{
                'testIdentifier': 'JournalOpenStateUITests/testDelete()', 'attachments': [{
                    'exportedFileName': 'shot.png',
                    'suggestedHumanReadableName': 'manual-crud-after-confirmed-delete_0_UUID.png'}]}]))
            output = raw / 'mirror.log'
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(module.mirror(raw, output), 1)
            self.assertEqual(stdout.getvalue(), '')
            lines = output.read_text().splitlines()
            chunks = [line.split(' ', 2)[2] for line in lines if line.startswith('SNAPSHOT-CHUNK ')]
            self.assertEqual(base64.b64decode(''.join(chunks)), payload)
            self.assertIn(hashlib.sha256(payload).hexdigest(), lines[0])
            self.assertEqual(lines[1], 'SNAPSHOT-BEGIN manual-crud-after-confirmed-delete ' + str(len(base64.b64encode(payload))))
            self.assertEqual(lines[-1], 'SNAPSHOT-END manual-crud-after-confirmed-delete')
            self.assertTrue(all(len(chunk) <= 4000 for chunk in chunks))

    def test_no_export_is_an_explicit_failure_not_fake_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = Path(directory)
            with self.assertRaises(FileNotFoundError):
                module.mirror(raw, raw / 'mirror.log')
            (raw / 'manifest.json').write_text('[]')
            with self.assertRaises(ValueError):
                module.mirror(raw, raw / 'mirror.log')

    def test_missing_or_escaping_png_is_not_silently_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = Path(directory)
            for filename, error in [('missing.png', FileNotFoundError), ('../escaping.png', ValueError)]:
                (raw / 'manifest.json').write_text(json.dumps([{
                    'testIdentifier': 'JournalOpenStateUITests/testDelete()', 'attachments': [{'exportedFileName': filename}]}]))
                with self.assertRaises(error):
                    module.mirror(raw, raw / 'mirror.log')

    def test_entire_native_file_restores_original_hash_and_rejects_changed_assertion(self):
        key = 'source:AteUITests/JournalOpenStateUITests.swift'
        source = (ROOT / key.removeprefix('source:')).read_text()
        expected = '7c30ca74937c4b35b041b324a12bdc2fe7200384516384c05aa2febaff5abfaf'
        self.assertEqual(hashlib.sha256(restore(key, source).encode()).hexdigest(), expected)
        for changed in [source.replace(NEW, '', 1), source + NEW, source.replace(NEW_COMMENT, '', 1)]:
            with self.assertRaises(AssertionError):
                restore(key, changed)
        changed = source.replace('XCTAssertFalse(app.staticTexts["journal.delete.error"].exists', 'XCTAssertTrue(app.staticTexts["journal.delete.error"].exists', 1)
        self.assertNotEqual(hashlib.sha256(restore(key, changed).encode()).hexdigest(), expected)
        self.assertNotIn('print(', source.split('private func shot(', 1)[1].split('/// The journal timeline', 1)[0])

    def test_export_then_mirror_then_upload_and_native_budget_unchanged(self):
        workflow = (ROOT / '.github/workflows/journal-open-state-ui.yml').read_text()
        self.assertLess(workflow.index('- name: Export rendered screenshots'), workflow.index('- name: Mirror retained Journal screenshots after XCTest'))
        self.assertLess(workflow.index('- name: Mirror retained Journal screenshots after XCTest'), workflow.index('- name: Upload diagnostics'))
        self.assertIn('journal-snapshot-mirror.log', workflow.split('- name: Upload diagnostics', 1)[1])
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480', workflow)
        step = next(s for s in yaml.safe_load(workflow)['jobs']['open-state-ui']['steps'] if s.get('name') == 'Mirror retained Journal screenshots after XCTest')
        self.assertEqual(step['if'], 'always()')
        self.assertEqual(subprocess.run(['bash', '-n'], input=step['run'], text=True, capture_output=True).returncode, 0)

    def test_entire_workflow_restores_exact_original(self):
        source = (ROOT / '.github/workflows/journal-open-state-ui.yml').read_text()
        additions = ['      - name: Mirror retained Journal screenshots after XCTest\n        if: always()\n        run: |\n          python3 scripts/mirror-journal-snapshots.py --raw-directory ui-screenshots/raw --output journal-snapshot-mirror.log\n', '            journal-snapshot-mirror.log\n']
        for addition in additions:
            self.assertEqual(source.count(addition), 1)
            source = source.replace(addition, '', 1)
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), '0bd051599259cdb676b361f920e646dea7d08a0cca9730cec6d3cdcca833a83f')
