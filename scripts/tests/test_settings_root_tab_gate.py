"""Required named invocation for the additive Settings visibility contract."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SettingsRootTabGateTests(unittest.TestCase):
    def test_required_named_settings_invocation_and_diagnostics(self):
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        gate = source.split('      - name: Settings root tab visibility contract (#526)', 1)[1].split('      - name: Settings-tab key-flow regression test', 1)[0]
        self.assertIn("matrix.suite == 'account-cooking'", gate)
        self.assertIn('-only-testing:AteUITests/SettingsRootTabVisibilityUITests/testSettingsScrollKeepsJournalTabVisibleWithoutRevealGesture', gate)
        self.assertIn("SettingsRootTabVisibilityUITests testSettingsScrollKeepsJournalTabVisibleWithoutRevealGesture]' passed", gate)
        self.assertIn('Executed 0 tests', gate)
        self.assertIn('exit 1', gate)
        self.assertNotIn('continue-on-error', gate)
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', gate)
        self.assertIn('navigation-header-tests.log settings-root-tab-visibility-tests.log cook-mode-history.log', source)
        self.assertIn('            settings-root-tab-visibility-tests.log\n', source)

        self.assertIn('CODE_SIGNING_ALLOWED=NO > settings-root-tab-visibility-tests.log 2>&1', gate)
        self.assertNotIn('settings-root-tab-visibility.log', source)
