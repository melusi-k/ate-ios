"""Permanent Files Cancel device boundary, no change to any native test body."""
from pathlib import Path
import unittest,yaml
ROOT=Path(__file__).resolve().parents[2]
NAME='CanonicalUpgradeUITests/testActualFilesPickerCancellationDoesNotShowImportErrorOrAddMeal'

class FilesCancelDeviceOnlyTests(unittest.TestCase):
    def test_no_ci_positive_selector_and_explicit_journal_skip(self):
        journal=(ROOT/'.github/workflows/journal-open-state-ui.yml').read_text()
        self.assertIn('-skip-testing:AteUITests/'+NAME,journal)
        self.assertNotIn('files_cancel_diagnostic',journal)
        self.assertNotIn('files-cancel-system-diagnostic.xcresult',journal)
        self.assertIn('DEVICE-ONLY, not run in CI',journal)
        for path in (ROOT/'.github/workflows').glob('*.yml'):
            self.assertNotIn('-only-testing:AteUITests/'+NAME,path.read_text())
        parsed=yaml.safe_load(journal)
        import subprocess
        for job in parsed['jobs'].values():
            for step in job.get('steps',[]):
                if step.get('name')=='Record device-only Files cancellation check':
                    subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)

    def test_device_case_names_real_path_no_sample_and_no_claimed_pass(self):
        doc=(ROOT/'docs/files-picker-cancel-device-check.md').read_text()
        for token in ['Settings → Food diary','Restore your JSON meal backup','Cancel','no new import error','no added meal','pending','No JSON sample']:
            self.assertIn(token,doc)
        source=(ROOT/'AteUITests/CanonicalUpgradeUITests.swift').read_text()
        self.assertIn('// DEVICE-ONLY permanently:',source)
