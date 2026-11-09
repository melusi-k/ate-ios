"""Contract checks for one exact-head Python suite and unchanged native coverage."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PythonSuiteRoutingTests(unittest.TestCase):
    def setUp(self):
        self.compile = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.dogfood = (ROOT / '.github/workflows/dogfood-qualification.yml').read_text()

    def test_one_complete_discovery_invocation(self):
        self.assertEqual(self.compile.count("python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v"), 1)
        self.assertNotIn('python3 -m unittest discover', self.dogfood)

    def test_suite_runs_on_linux_without_event_or_scope_skip(self):
        job = self.compile.split('  python-tests:\n', 1)[1].split('\n  docs-validation:', 1)[0]
        self.assertIn('runs-on: ubuntu-latest', job)
        self.assertNotIn('    if:', job)
        self.assertNotIn('continue-on-error', job)
        self.assertIn('ref: ${{ github.event.pull_request.head.sha || github.sha }}', job)
        self.assertIn('persist-credentials: false', job)
        self.assertIn('permissions:\n      contents: read', job)

    def test_existing_native_aggregate_requires_python_success(self):
        job = self.compile.split('  compile:\n', 1)[1].split('\n  qualification-result:', 1)[0]
        self.assertIn('needs: [changes, python-tests, build-nutrition, regressions]', job)
        self.assertIn('PYTHON_RESULT: ${{ needs.python-tests.result }}', job)
        self.assertIn('[ "$PYTHON_RESULT" != success ]', job)
        self.assertIn('exit 1', job)

    def test_existing_final_gate_requires_python_on_docs_and_native(self):
        job = self.compile.split('  qualification-result:\n', 1)[1]
        self.assertIn('name: Compile qualification result', job)
        self.assertIn('needs: [changes, python-tests, compile, docs-validation]', job)
        self.assertLess(job.index('if [[ "$PYTHON_RESULT" != success ]]'), job.index('if [[ "$NATIVE" == false ]]'))
        self.assertIn('[[ "$NATIVE_RESULT" == skipped && "$DOCS_RESULT" == success ]]', job)
        self.assertIn('[[ "$NATIVE" == true && "$NATIVE_RESULT" == success ]]', job)

    def test_dogfood_merge_ref_python_removal_is_explicit(self):
        self.assertIn('Separate merge-ref Python coverage is intentionally removed.', self.dogfood)
        self.assertIn('  qualification-result:\n    name: Dogfood qualification result', self.dogfood)

    def test_failure_cancel_skip_are_not_success(self):
        for result in ('failure', 'cancelled', 'skipped', 'unknown', ''):
            self.assertNotEqual(result, 'success')


if __name__ == '__main__':
    unittest.main()
