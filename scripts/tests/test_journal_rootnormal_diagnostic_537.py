from pathlib import Path
import hashlib,unittest,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class JournalRootnormalDiagnosticTests(unittest.TestCase):
    def test_entire_original_ui_source_unchanged_except_flag(self):
        s=(ROOT/'AteUITests/JournalOpenStateUITests.swift').read_text().replace('"-qaJournalAnimationDiagnostic", ','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'7c30ca74937c4b35b041b324a12bdc2fe7200384516384c05aa2febaff5abfaf')
    def test_bounded_sampler_and_covered_window(self):
        s=(ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text().split('enum JournalAnimationDiagnostics {')[1]
        for x in ['AppConfig.isUITesting','-qaJournalAnimationDiagnostic','@MainActor','Task.sleep','visited < 2048','depth < 64','emitted < 64','prefix(8)','main-actor-heartbeat','elapsed=']:self.assertIn(x,s)
        self.assertNotIn('CoverStore',s)
        self.assertNotIn('debugDescription',s)
        w=yaml.safe_load((ROOT/'.github/workflows/journal-open-state-ui.yml').read_text())
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if 'journal-rootnormal-window' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(p.returncode,0,p.stderr)
