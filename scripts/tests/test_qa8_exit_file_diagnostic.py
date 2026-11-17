from password_save_prompt_delta import restore as restore_password_prompt
from pathlib import Path
import unittest,hashlib,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class QA8ExitFileTests(unittest.TestCase):
    def test_original_ui_source_except_only_flag(self):
        s=restore_password_prompt('source:AteUITests/KeyFlowsQATests.swift',(ROOT/'AteUITests/KeyFlowsQATests.swift').read_text()).replace(', "-qaQA8ExitFileDiagnostic"','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'51d079b57384dcfe5474d72442f09bf1c97de9d922b4ce287fe6df3b98750fbe')
    def test_original_exit_body_except_diagnostic_hooks(self):
        s=(ROOT/'Ate/Views/CookModeView.swift').read_text().replace('\n        #if DEBUG\n        QA8ExitFileDiagnostic.exitWillBegin()\n        defer { QA8ExitFileDiagnostic.exitDidReturn() }\n        #endif','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'51835197b46eaa3e028d070890e9a3911ed3061efd1ac704dce18fc70105eef0')
    def test_bounded_numeric_file_and_no_waiting_collector(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text()
        s=source.split('enum QA8ExitFileDiagnostic {')[1]
        for token in ['AppConfig.isUITesting','-qaQA8ExitFileDiagnostic','rows.count < 24','.atomic','@MainActor','Task.sleep','[0.0, 5, 15, 30, 45, 60, 90, 120]']:self.assertIn(token,s)
        for token in ['CoverStore','debugDescription','recipeID']:self.assertNotIn(token,s)
        w=yaml.safe_load((ROOT/'.github/workflows/dogfood-qualification.yml').read_text())
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if 'qa8-exit-file' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(p.returncode,0,p.stderr)
                    self.assertNotIn('sleep ',step['run'])

    def test_paired_scheduler_is_bounded_and_original_files_unchanged(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text().split('enum QA8ExitFileDiagnostic {')[1]
        self.assertEqual(s.count('[0.0, 5, 15, 30, 45, 60, 90, 120]'),2)
        self.assertIn('Task { @MainActor in\n            record("task-entered"',s)
        for phase in ['sampler-enqueued','task-cancelled','task-sleep-error','scheduler-enqueued','scheduler-entered','scheduler-fired','scheduler-main-delivery','scheduler-complete']:
            self.assertIn('"'+phase+'"',s)
        self.assertIn('schedulerRows.count < 10',s)
        self.assertIn('qos: .utility',s)
        self.assertNotIn('Task.detached',s)
        self.assertNotIn('while ',s)
        originals = {'AteUITests/KeyFlowsQATests.swift': '9085fc97e340f248bd5b101a479b02d451ddfdac42a7e8c216709ef88d2c930c', 'Ate/Views/CookModeView.swift': 'e72c1e3491d903b37751ab96d5eb044859ee569735816ad0de98dcc7a5877b9a'}
        for f,digest in originals.items():
            self.assertEqual(hashlib.sha256(restore_password_prompt('source:'+f,(ROOT/f).read_bytes())).hexdigest(),digest)
