from approved_merge_534 import normalize
from pathlib import Path
import hashlib,unittest,yaml,subprocess,ast
ROOT=Path(__file__).resolve().parents[2]
STEP="      - name: Retain Account month and completion assertion captures\n        if: ${{ matrix.suite == 'account-cooking' && always() }}\n        run: |\n          python3 - <<'PYEXPORT'\n          import os, pathlib, subprocess\n          root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'ate-test-results'\n          for name in ['cook-mode-history-ui-tests', 'cooking-tracker-ui-tests']:\n              source = root / (name + '.xcresult')\n              output = root / (name + '-attachments')\n              output.mkdir(parents=True, exist_ok=True)\n              note = output / 'export-status.txt'\n              if not source.is_dir():\n                  note.write_text('Source xcresult missing; captures unavailable.\\n')\n                  continue\n              try:\n                  result = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments',\n                      '--path', str(source), '--output-path', str(output)],\n                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)\n                  note.write_text('export_exit=' + str(result.returncode) + '\\n' + result.stdout)\n                  if result.returncode:\n                      print('::warning::Attachment export failed for ' + name + '; see export-status.txt')\n              except subprocess.TimeoutExpired:\n                  note.write_text('Attachment export exceeded 60 seconds and was stopped; partial captures may remain.\\n')\n                  print('::warning::Attachment export timed out for ' + name)\n              except OSError as error:\n                  note.write_text('Attachment export could not start: ' + str(error) + '\\n')\n                  print('::warning::Attachment export unavailable for ' + name)\n          PYEXPORT\n\n"
EXTRA='            ${{ runner.temp }}/ate-test-results/cook-mode-history-ui-tests-attachments\n            ${{ runner.temp }}/ate-test-results/cooking-tracker-ui-tests-attachments\n'
class AccountCaptureExportTests(unittest.TestCase):
    def test_only_export_and_upload_additions(self):
        source=normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text())
        self.assertEqual(source.count(STEP),1)
        self.assertEqual(source.count(EXTRA),2)
        restored=source.replace(STEP,'',1).replace(EXTRA,'')
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),'828e6a88d60b3e88952c8f093f697375c9131df12bddc47122a09421a1323a4c')
    def test_always_run_bounded_two_exports_and_honest_notes(self):
        self.assertIn("matrix.suite == 'account-cooking' && always()",STEP)
        self.assertIn('timeout=60',STEP)
        self.assertIn('except subprocess.TimeoutExpired',STEP)
        self.assertIn('Source xcresult missing',STEP)
        workflow=yaml.safe_load(normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text()))
        for job in workflow['jobs'].values():
            for step in job.get('steps',[]):
                if step.get('name')=='Retain Account month and completion assertion captures':
                    run=step['run']
                    result=subprocess.run(['bash','-n'],input=run,text=True,capture_output=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    ast.parse(run.split("<<'PYEXPORT'\n",1)[1].split('\nPYEXPORT',1)[0])
