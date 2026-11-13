"""The added AX contract must execute and fail closed, not remain an unrun file."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class RecipeStaticRowGateTests(unittest.TestCase):
    def test_separate_required_named_invocation_and_diagnostics(self):
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        gate = source.split('      - name: Static recipe row accessibility contract (#522)', 1)[1].split('      - name: Settings-tab key-flow regression test', 1)[0]
        self.assertIn("matrix.suite == 'presentation-creation'", gate)
        self.assertIn('-only-testing:AteUITests/RecipeStaticRowAccessibilityUITests/testCombinedRecipeRowsRetainQuantityNameStepNumberAndInstruction', gate)
        self.assertIn("RecipeStaticRowAccessibilityUITests testCombinedRecipeRowsRetainQuantityNameStepNumberAndInstruction]' passed", gate)
        self.assertIn('Executed 0 tests', gate)
        self.assertIn('exit 1', gate)
        self.assertNotIn('continue-on-error', gate)
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', gate)
        self.assertIn('expandable-recipe-sheet-tests.log recipe-static-row-accessibility-tests.log', source)
        self.assertIn('            recipe-static-row-accessibility-tests.log\n', source)

        self.assertIn('CODE_SIGNING_ALLOWED=NO > recipe-static-row-accessibility-tests.log 2>&1', gate)
        self.assertNotIn('recipe-static-row-accessibility.log', source)
