from pathlib import Path
import unittest,hashlib,yaml,subprocess
ROOT=Path(__file__).resolve().parents[2]
class DeleteCancelLivenessTests(unittest.TestCase):
    def test_original_ui_and_cancel_semantics_reconstruct_exact_source(self):
        originals = {'AteUITests/JournalOpenStateUITests.swift': '20be8714b865f03d4857f4daae644720c6fd921a0692e9f10dc59ef200651b3b', 'Ate/Views/JournalDeleteConfirmation.swift': '02ab29bb3980d479452de6e9f241c7bf8ec5bdcf6c5ee48c347bdb2b8ef63041'}
        replacements = {
            'AteUITests/JournalOpenStateUITests.swift': [('composeFromHistory(extra: ["-qaPresentationReturnDiagnostic"])','composeFromHistory()'),('        shot("manual-crud-after-delete-cancel-before-original-predicate")\n','')],
            'Ate/Views/JournalDeleteConfirmation.swift': [('        }, onCancel: {\n            isPresented = false\n            #if DEBUG\n            PresentationReturnDiagnostic.returnedIfRequested()\n            #endif\n        })','        }, onCancel: { isPresented = false })')]
        }
        for f,digest in originals.items():
            s=(ROOT/f).read_text()
            for a,b in replacements[f]:
                self.assertEqual(s.count(a),1)
                s=s.replace(a,b)
            self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),digest)
    def test_paired_bounds_and_collector(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text().split('enum PresentationReturnDiagnostic {')[1]
        for token in ['AppConfig.isUITesting','-qaPresentationReturnDiagnostic','rows.count < 24','schedulerRows.count < 10','task-entered','delete-cancel-action-return']:
            self.assertIn(token,s)
        self.assertEqual(s.count('[0.0, 5, 15, 30, 45, 60, 90, 120]'),2)
        for token in ['CoverStore','debugDescription','store.','while ']:self.assertNotIn(token,s)
        w=yaml.safe_load((ROOT/'.github/workflows/journal-open-state-ui.yml').read_text())
        for j in w['jobs'].values():
            for step in j.get('steps',[]):
                if 'journal-return-window' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True)
                    self.assertEqual(p.returncode,0,p.stderr)
