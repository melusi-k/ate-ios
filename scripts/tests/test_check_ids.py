"""Regression checks for the acceptance-ID and release-gate contract."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class GateContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for relative in (
            'scripts/check-ids.py', 'scripts/gen-beta-checklist.py',
            'docs/MVP_CHECKLIST.md', 'docs/QA_MATRIX.md', 'docs/LAUNCH_GATES.md',
            'Ate/Logic/BetaChecklist.swift',
        ):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)

    def edit(self, relative, old, new):
        path = self.root / relative
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1))

    def check(self, expected=None):
        result = subprocess.run(
            [sys.executable, str(self.root / 'scripts/check-ids.py')],
            text=True, capture_output=True,
        )
        output = result.stdout + result.stderr
        if expected is None:
            self.assertEqual(result.returncode, 0, output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
            self.assertIn(expected, output)

    def test_current_inventory_passes(self):
        self.check()

    def test_documented_gate_count_drift_fails(self):
        self.edit('docs/LAUNCH_GATES.md', '| 96 |', '| 95 |')
        self.check('Pilot count 96 differs from LAUNCH_GATES 95')

    def test_documented_total_drift_fails(self):
        self.edit('docs/LAUNCH_GATES.md', '| 179 |', '| 180 |')
        self.check('total acceptance ID count must match')

    def test_missing_gate_count_fails(self):
        self.edit('docs/LAUNCH_GATES.md', '`Pilot`', '`Other`')
        self.check('expected exactly one count for Pilot')

    def test_matrix_gate_change_fails(self):
        self.edit('docs/QA_MATRIX.md', '| Pilot | P1 |', '| Public launch | P1 |')
        self.check('Release gate differs between MVP_CHECKLIST and QA_MATRIX')

    def test_checklist_gate_change_fails(self):
        self.edit('docs/MVP_CHECKLIST.md', '*Release gate:* Pilot', '*Release gate:* Public launch')
        self.check('Release gate differs between MVP_CHECKLIST and QA_MATRIX')

    def test_matching_reclassification_requires_updated_counts(self):
        self.edit('docs/MVP_CHECKLIST.md', '*Release gate:* Pilot', '*Release gate:* Public launch')
        self.edit('docs/QA_MATRIX.md', '| Pilot | P1 |', '| Public launch | P1 |')
        self.check('Pilot count 95 differs from LAUNCH_GATES 96')

    def test_unknown_matrix_gate_fails(self):
        self.edit('docs/QA_MATRIX.md', '| Pilot | P1 |', '| Typo | P1 |')
        self.check('invalid or missing Release gate in QA_MATRIX')

    def test_unknown_checklist_gate_fails(self):
        self.edit('docs/MVP_CHECKLIST.md', '*Release gate:* Pilot', '*Release gate:* Typo')
        self.check('invalid or missing Release gate in MVP_CHECKLIST')

    def test_duplicate_matrix_row_fails_even_when_unique_counts_match(self):
        path = self.root / 'docs/QA_MATRIX.md'
        text = path.read_text()
        row = next(line for line in text.splitlines() if line.startswith('| A-CREATE-01 |'))
        path.write_text(text + '\n' + row + '\n')
        self.check('A-CREATE-01: defined more than once in QA_MATRIX')

    def test_missing_matrix_row_fails(self):
        path = self.root / 'docs/QA_MATRIX.md'
        path.write_text('\n'.join(line for line in path.read_text().splitlines()
                                  if not line.startswith('| A-CREATE-01 |')) + '\n')
        self.check('A-CREATE-01: in MVP_CHECKLIST but has no actual QA_MATRIX row')

    def test_extra_matrix_id_fails(self):
        path = self.root / 'docs/QA_MATRIX.md'
        path.write_text(path.read_text() + '\n| A-EXTRA-99 | Extra | General | Pilot | P1 |\n')
        self.check('A-EXTRA-99: cited in docs/QA_MATRIX.md but not defined')


if __name__ == '__main__':
    unittest.main()
