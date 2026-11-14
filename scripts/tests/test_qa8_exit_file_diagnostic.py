from pathlib import Path
import unittest,hashlib,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class QA8ExitFileTests(unittest.TestCase):
    def test_original_ui_source_except_only_flag(self):
        s=(ROOT/'AteUITests/KeyFlowsQATests.swift').read_text().replace(', "-qaQA8ExitFileDiagnostic"','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'51d079b57384dcfe5474d72442f09bf1c97de9d922b4ce287fe6df3b98750fbe')
    def test_original_exit_body_except_diagnostic_hooks(self):
        s=(ROOT/'Ate/Views/CookModeView.swift').read_text().replace('\n        #if DEBUG\n        QA8ExitFileDiagnostic.exitWillBegin()\n        defer { QA8ExitFileDiagnostic.exitDidReturn() }\n        #endif','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'51835197b46eaa3e028d070890e9a3911ed3061efd1ac704dce18fc70105eef0')
    def test_bounded_numeric_file_and_no_waiting_collector(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text()
        s=source.split('enum QA8ExitFileDiagnostic {')[1]
        for token in ['AppConfig.isUITesting','-qaQA8ExitFileDiagnostic','rows.count < 12','.atomic','@MainActor','Task.sleep','[0.0, 5, 15, 30, 45, 60, 90, 120]']:self.assertIn(token,s)
        for token in ['CoverStore','debugDescription','recipeID']:self.assertNotIn(token,s)
        w=yaml.safe_load((ROOT/'.github/workflows/dogfood-qualification.yml').read_text())
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if 'qa8-exit-file' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(p.returncode,0,p.stderr)
                    self.assertNotIn('sleep ',step['run'])
