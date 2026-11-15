from approved_merge_539 import normalize
from pathlib import Path
import hashlib
from test_menu_favourite_capture import restore_menu_capture_ui
import unittest
ROOT=Path(__file__).resolve().parents[2]
class DogWaitPhaseDiagnosticTests(unittest.TestCase):
    def test_original_entire_test_files_survive_only_diagnostics(self):
        cases=[('AteUITests/AteUITests.swift','library-reorder-after-longpress','cae9f4db8b33808430f2e9b575ddd9f7c45662e0d2df0942d84b441cf67a2d92'),('AteUITests/KeyFlowsQATests.swift','8-after-exit-before-timerbar-query','c07bdfa3a5a831f9fac67e546a6ab6607e73f141f7f6793cd8d1d6c6bb69d629')]
        for file,pixel,digest in cases:
            s=normalize('source:'+file,(ROOT/file).read_text())
            if file == "AteUITests/AteUITests.swift": s=restore_menu_capture_ui(s)
            s=s.replace('launch(["-qaDogWaitPhaseDiagnostic"])','launch()').replace(', "-qaDogWaitPhaseDiagnostic"','').replace(', "-qaQA8ExitFileDiagnostic"','')
            s=s.replace('\n        shot("'+pixel+'")','')
            self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),digest)
    def test_flagged_bounded_main_actor_sampler(self):
        source=normalize('source:Ate/App/AteApp.swift', (ROOT/'Ate/App/AteApp.swift').read_text())
        for module in ['UIKit','OSLog']:
            self.assertIn('import '+module, source.split('@main')[0])
        s=source.split('enum DogWaitPhaseDiagnostics {',1)[1]
        for token in ['-qaDogWaitPhaseDiagnostic','main-actor-heartbeat','AppConfig.isUITesting','Task.sleep','visited < 2048','emitted < 64']:
            self.assertIn(token,s)

    def test_collection_covers_critical_step_and_survives_failure(self):
        import yaml, subprocess
        source=normalize('source:.github/workflows/dogfood-qualification.yml', (ROOT/'.github/workflows/dogfood-qualification.yml').read_text())
        self.assertIn('dogfood-critical-window/start-utc.txt',source)
        self.assertIn('trap ',source)
        self.assertIn('            dogfood-critical-window\n',source)
        workflow=yaml.safe_load(source)
        for job in workflow['jobs'].values():
            for step in job.get('steps',[]):
                if step.get('name') in ['Required critical flows and Library popup journeys','Retain bounded critical-flow unified-log window']:
                    result=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True)
                    self.assertEqual(result.returncode,0,result.stderr)
        app=normalize('source:Ate/App/AteApp.swift', (ROOT/'Ate/App/AteApp.swift').read_text()).split('enum DogWaitPhaseDiagnostics {',1)[1]
        self.assertNotIn('CoverStore',app)
