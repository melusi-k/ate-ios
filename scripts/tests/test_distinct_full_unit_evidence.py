"""Additive exact-source evidence cannot replace or alter existing native gates."""
from pathlib import Path
import hashlib
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]


class DistinctFullUnitEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.workflow = (ROOT / '.github/workflows/exact-head-full-units.yml').read_text()
        self.original = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.job = yaml.safe_load(self.workflow)['jobs']['full-units']

    def test_build_full_unit_gate_and_artifacts_are_byte_carried(self):
        start = '      - name: Prepare diagnostics directory'
        old = self.original.split(start, 1)[1].split('      # Keep normal-size audits', 1)[0]
        new = self.workflow.split(start, 1)[1].split('      - name: Verify source identity after native execution', 1)[0]
        self.assertEqual(old, new)
        self.assertIn('python3 scripts/verify-full-unit-required.py full-unit-tests.json scripts/full-unit-required.txt', new)
        self.assertIn('-only-testing:AteTests', new)
        self.assertNotIn('continue-on-error', self.workflow)

    def test_scoped_push_and_manual_exact_source_without_clip_retry_or_extra_budget(self):
        # PyYAML's YAML1.1 treats the key `on` as boolean True.
        events = yaml.safe_load(self.workflow)[True]
        self.assertEqual(list(events), ['push', 'workflow_dispatch'])
        self.assertEqual(events['push']['branches'], ['ci/distinct-exact-head-full-units'])
        self.assertIn('8847434f1729d3f6234b66943e78744816574521', self.job['env']['SOURCE_SHA'])
        self.assertEqual(self.job['runs-on'], 'xcode-27')
        self.assertEqual(self.job['timeout-minutes'], 45)
        self.assertNotIn('concurrency:', self.workflow)
        self.assertNotIn('AteClip', self.workflow)
        for literal in ['^[0-9a-f]{40}$', 'ref: ${{ env.SOURCE_SHA }}',
                        'persist-credentials: false', 'xcode-version: "27.1"',
                        'test "$(git rev-parse HEAD)" = "$SOURCE_SHA"']:
            self.assertIn(literal, self.workflow)
        self.assertEqual(self.workflow.count('test "$(git rev-parse HEAD)" = "$SOURCE_SHA"'), 2)

    def test_existing_compile_workflow_is_frozen(self):
        self.assertEqual(hashlib.sha256(self.original.encode()).hexdigest(),
                         'dfe6d1f533c44956b71590653e8091ac0d4e7e71efb073499c0fb01fa0341f4c')
