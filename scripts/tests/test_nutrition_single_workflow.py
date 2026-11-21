"""Manual-only exact-head single-test execution, never a gate substitute."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT/'.github/workflows/nutrition-failed-save-single.yml'
TARGET = 'NutritionDiaryUITests testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch'

class SingleNutritionWorkflowTests(unittest.TestCase):
    def test_manual_only_exact_selection_pins_caps_and_no_retry(self):
        text = WORKFLOW.read_text()
        trigger = text.split('\non:\n',1)[1].split('\npermissions:',1)[0]
        self.assertEqual(trigger.strip(), 'workflow_dispatch:')
        self.assertEqual(text.count('-only-testing:'), 1)
        self.assertIn('-only-testing:AteUITests/'+TARGET.replace(' ','/'),text)
        for required in ['runs-on: xcode-27', 'xcode-version: "27.1"', 'scripts/select-ios-simulator.py',
                         'ref: ${{ github.sha }}', 'EXPECTED_HEAD: ${{ github.sha }}',
                         'test "$RUN_ATTEMPT" = 1', '-default-test-execution-time-allowance 240',
                         '-maximum-test-execution-time-allowance 480', '-parallel-testing-enabled NO',
                         'set -euo pipefail', 'if: always()', 'actions/upload-artifact@v7']:
            self.assertIn(required,text)
        self.assertEqual(text.count('xcodebuild build-for-testing '),1)
        self.assertEqual(text.count('xcodebuild test-without-building '),1)
        self.assertNotIn('-retry-tests-on-failure',text)
        self.assertNotIn('-test-iterations',text)
        self.assertNotIn('-skip-testing:',text)
        self.assertNotIn('continue-on-error',text)
        self.assertNotIn('pull_request:',text)
        self.assertNotIn('push:',text)

    def test_exact_pass_and_zero_failure_duplicate_watchdog_mutants(self):
        text = WORKFLOW.read_text()
        verifier = text.split("          python3 - <<'PYVERIFY'\n",1)[1].split('          PYVERIFY',1)[0]
        verifier = '\n'.join(line[10:] for line in verifier.splitlines())
        start = "Test Case '-[AteUITests."+TARGET+"]' started.\n"
        passed = "Test Case '-[AteUITests."+TARGET+"]' passed (42.2 seconds).\n"
        success = '** TEST EXECUTE SUCCEEDED **\n'
        good = start+passed+success
        cases = [(good,True),('',False),(success,False),(good.replace('42.2','0.000'),False),
                 (start+start+passed+success,False),(good+good,False),
                 (good+'Test exceeded execution time allowance\n',False),
                 (good+'Restarting after unexpected exit\n',False),
                 (good+'** TEST EXECUTE FAILED **\n',False),
                 (good+"Test Case '-[Other testOther]' started.\n",False),
                 (good.replace('passed (42.2 seconds).','failed (42.2 seconds).'),False)]
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory)/'build/nutrition-failed-save-single/journey.log'
            log.parent.mkdir(parents=True)
            for content, expected in cases:
                log.write_text(content)
                result = subprocess.run([sys.executable,'-c',verifier],cwd=directory,capture_output=True)
                self.assertEqual(result.returncode==0,expected,(content,result.stderr.decode()))

if __name__ == '__main__':
    unittest.main()
