from approved_merge_composed import normalize
from pathlib import Path
import hashlib,unittest,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class AccountJourneyDiagnosticTests(unittest.TestCase):
    def test_original_entire_ui_sources_retained(self):
        for file,digest in {'AteUITests/CookingTrackerEntryUITests.swift': '4e403c9f0c3e36db7972139d823c68ae8373037beef9c62591ca3a7072f82883', 'AteUITests/AteUITests.swift': '5484221d8e4c89265c1d6601413fa74abe7c3c67e8093ec85e09a220fa243ad9'}.items():
            s=normalize('source:'+file,(ROOT/file).read_text()).replace('["-qaAccountJourneyAnimationDiagnostic"]','').replace(', "-qaPresentationReturnDiagnostic"','').replace('        shot("68-journal-after-native-back-before-original-predicate")\n','')
            import re
            s=re.sub(r'    private func startupDiagnosticMark\(_ phase: String\) \{.*?\n    \}\n', '', s, flags=re.S)
            s='\n'.join(line for line in s.split('\n') if 'startupDiagnosticMark(' not in line)
            s=s.replace(', "-qaStartupLivenessDiagnostic"','')
            self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),digest,file)
    def test_bounded_sampler_and_step_windows(self):
        file=normalize('source:Ate/App/DogfoodSavedRecipeQAFixtures.swift', (ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text())
        for module in ['UIKit','OSLog']:
            self.assertIn('import '+module, file.split('enum DogfoodSavedRecipeQAFixtures')[0])
        s=file.split('enum AccountJourneyAnimationDiagnostics {')[1]
        for t in ['AppConfig.isUITesting','-qaAccountJourneyAnimationDiagnostic','@MainActor','Task.sleep','visited < 2048','depth < 64','emitted < 64','prefix(8)','main-actor-heartbeat','elapsed=']:self.assertIn(t,s)
        self.assertNotIn('CoverStore',s)
        w=yaml.safe_load(normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text()))
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if any(d in step.get('run','') for d in ['tracker-query-window','cook-completion-window']):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(p.returncode,0,p.stderr)
