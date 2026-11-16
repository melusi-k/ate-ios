from pathlib import Path
import hashlib,unittest,subprocess,yaml
ROOT=Path(__file__).resolve().parents[2]
class SettingsQueryDiagnosticTests(unittest.TestCase):
    def test_original_failed_save_body_retained(self):
        s=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        b=s.split('    func testCancelledFailedSavesLeaveDiaryEmptyAfterRelaunch()',1)[1].split('\n    func ',1)[0]
        b=b.replace(', "-qaSettingsQueryDiagnostic"','').replace('        captureSettingsQuery = true\n        defer { captureSettingsQuery = false }\n','').replace('        captureSettingsQuery = false\n','')
        self.assertEqual(hashlib.sha256(b.encode()).hexdigest(),'9fa0c2d1cbc81d008da46d787c6f71f204834bdca4a683ce0e9dabdce0b248b6')
    def test_bounded_opt_in_and_retained_log_window(self):
        app=(ROOT/'Ate/App/AteApp.swift').read_text().split('private enum SettingsQueryDiagnostic {',1)[1]
        for t in ['AppConfig.isUITesting','-qaSettingsQueryDiagnostic','@MainActor','[0.0, 15, 30, 60, 90, 120, 150, 180, 210]','Task.sleep']:self.assertIn(t,app)
        workflow=yaml.safe_load((ROOT/'.github/workflows/compile-check.yml').read_text())
        for job in workflow['jobs'].values():
            for step in job.get('steps',[]):
                if step.get('name') in ['Nutrition diary and goals UI regressions (#179)','Retain bounded nutrition query diagnostic window']:
                    p=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(p.returncode,0,p.stderr)
