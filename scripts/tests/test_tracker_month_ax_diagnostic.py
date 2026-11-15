from pathlib import Path
import hashlib,unittest,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class MonthAXDiagnosticTests(unittest.TestCase):
    def test_original_entire_test_source_preserved(self):
        s=(ROOT/'AteUITests/CookingTrackerEntryUITests.swift').read_text().replace('["-qaTrackerMonthAXDiagnostic"]','').replace('\n        // Evidence follows the original predicate. No retry/replacement of its result.\n        shot("tracker-month-after-original-previous-predicate")\n        print("TRACKER-MONTH-AFTER-PREDICATE-LABEL-BEGIN")\n        print(month.label)\n        print(month.debugDescription)\n        print("TRACKER-MONTH-AFTER-PREDICATE-LABEL-END")','')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'9476f761691f6967110957df448ea4d114aa9c3d6e5a12ab695ddd6fe2617e8e')
    def test_opt_in_and_shell(self):
        s=(ROOT/'Ate/Views/CookingTrackerView.swift').read_text()
        for token in ['-qaTrackerMonthAXDiagnostic','previous-before','previous-after','month-on-change']:self.assertIn(token,s)
        w=yaml.safe_load((ROOT/'.github/workflows/compile-check.yml').read_text())
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if 'tracker-month-window' in step.get('run',''):
                    r=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(r.returncode,0,r.stderr)
