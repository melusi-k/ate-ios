from pathlib import Path
import unittest,hashlib,yaml,subprocess
ROOT=Path(__file__).resolve().parents[2]
class PresentationReturnDiagnosticTests(unittest.TestCase):
    def test_original_entire_ui_except_flag_and_pixel(self):
        s=(ROOT/'AteUITests/CookingTrackerEntryUITests.swift').read_text().replace(', "-qaPresentationReturnDiagnostic"','').replace('        shot("68-journal-after-native-back-before-original-predicate")\n','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'708d15cd6f5c0b891bb3a3a12bae2d8eb3924a08c75635b49ff08268cd8b7394')
    def test_bounded_paired_observer_without_mutation(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text()
        for token in ['if !oldPath.isEmpty && newPath.isEmpty','PresentationReturnDiagnostic.returnedIfRequested()','AppConfig.isUITesting','-qaPresentationReturnDiagnostic','rows.count < 24','schedulerRows.count < 10','qos: .utility','task-entered','task-cancelled','task-sleep-error']:
            self.assertIn(token,s)
        d=s.split('enum PresentationReturnDiagnostic {')[1]
        self.assertEqual(d.count('[0.0, 5, 15, 30, 45, 60, 90, 120]'),2)
        for token in ['CoverStore','debugDescription','store.','while ']:self.assertNotIn(token,d)
        w=yaml.safe_load((ROOT/'.github/workflows/compile-check.yml').read_text())
        for j in w['jobs'].values():
            for step in j.get('steps',[]):
                if 'presentation-return-diagnostic.txt' in step.get('run',''):
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True)
                    self.assertEqual(p.returncode,0,p.stderr)
                    self.assertNotIn('simctl boot',step['run'])
