from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
# SHA256 pins from reviewed main 4abdad968cd563f9d2f3e3dbb562fec5f6bf8edd; no git history required.
class CookFinishRetryContracts(unittest.TestCase):
    def test_original_finish_pipeline_is_byte_identical(self):
        current=(ROOT/'Ate/Views/CookModeView.swift').read_text()
        def pipeline(s):return s.split('    private func finish(_ recipe: RecipeCard) {',1)[1].split('    /// After the user chose',1)[0].split('    /// Wait for the error presentation',1)[0]
        self.assertEqual(hashlib.sha256(pipeline(current).encode()).hexdigest(), '5abefa5e1d58ea22dd68a69041d24ed995e60ab8eac6c06afba2521fc9a453ba')
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
        pins = {
            'Ate/Logic/CookCompletion.swift': 'bc0612e94275911be3067fc82d695919fdacbb04774054b97b1031ca09827f1f',
            'Ate/Store/AppStore.swift': '09bf254a50d65f3f13c97e7f79a5444375bca885ce32f65f878a41fb573489c6',
        }
        for path, expected in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(), expected, path)
