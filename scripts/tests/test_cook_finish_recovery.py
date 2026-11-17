from pathlib import Path
import subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]
BASE='4abdad968cd563f9d2f3e3dbb562fec5f6bf8edd'
class CookFinishRetryContracts(unittest.TestCase):
    def test_original_finish_pipeline_is_byte_identical(self):
        current=(ROOT/'Ate/Views/CookModeView.swift').read_text()
        old=subprocess.check_output(['git','show',BASE+':Ate/Views/CookModeView.swift'],cwd=ROOT,text=True)
        def pipeline(s):return s.split('    private func finish(_ recipe: RecipeCard) {',1)[1].split('    /// After the user chose',1)[0].split('    /// Wait for the error presentation',1)[0]
        self.assertEqual(pipeline(current),pipeline(old))
    def test_explicit_recovery_waits_for_dismissal_and_preserves_failure_copy(self):
        source=(ROOT/'Ate/Views/CookModeView.swift').read_text()
        sheet=source.split('.sheet(isPresented: Binding(get: { finishProblem != nil }',1)[1].split('.sheet(item: $reflectionOffer',1)[0]
        self.assertIn('onDismiss: performRequestedFinishRecovery',sheet)
        self.assertIn('finishRecovery.request(.retry)',sheet)
        self.assertIn('finishRecovery.request(.setAside)',sheet)
        self.assertIn('Button("Not now", role: .cancel) { finishProblem = nil }',sheet)
        for forbidden in ['finish(recipe)', 'sleep(', 'Task {','asyncAfter','retryCount']:
            self.assertNotIn(forbidden,sheet)
        self.assertIn('Some changes may already be saved',sheet)
        handler=source.split('private func performRequestedFinishRecovery()',1)[1].split('/// After the user chose',1)[0]
        self.assertIn('finishRecovery.consume()',handler);self.assertIn('finish(recipe)',handler)
        self.assertNotIn('while ',handler)
    def test_no_completion_or_history_semantics_change(self):
        for path in ['Ate/Logic/CookCompletion.swift','Ate/Store/AppStore.swift']:
            old=subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
            self.assertEqual((ROOT/path).read_bytes(),old)
