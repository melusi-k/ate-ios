"""Duo arming is bounded to its dedicated UI bundle; normal gate stays fixed."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("arm_duo", ROOT / "scripts/enable-duo-exploration.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DuoExplorationTests(unittest.TestCase):
    def test_modern_xctestrun_targets_only_ui_bundle(self):
        unit = {"TestBundlePath": "__TESTROOT__/AteTests.xctest"}
        ui = {"TestBundlePath": "__TESTHOST__/PlugIns/AteUITests.xctest"}
        data = {"TestConfigurations": [{"TestTargets": [unit, ui]}]}
        self.assertEqual(module.enable(data), 1)
        self.assertNotIn("EnvironmentVariables", unit)
        self.assertEqual(ui["EnvironmentVariables"]["ATE_DUO_EXPLORATION"], "1")
    def test_legacy_preserves_other_environment(self):
        ui = {"TestBundlePath": "__TESTROOT__/AteUITests.xctest", "EnvironmentVariables": {"existing": "yes"}}
        self.assertEqual(module.enable({"AteUITests": ui}), 1)
        self.assertEqual(ui["EnvironmentVariables"]["existing"], "yes")
    def test_missing_target_not_armed(self):
        self.assertEqual(module.enable({"Other": {"TestBundlePath": "Other.xctest"}}), 0)
    def test_manual_workflow_and_gate_separate(self):
        workflow = (ROOT / ".github/workflows/duo-exploration.yml").read_text()
        self.assertIn("  workflow_dispatch:", workflow)
        self.assertNotIn("pull_request:", workflow)
        self.assertNotIn("  push:", workflow)
        self.assertIn("runs-on: xcode-27", workflow)
        self.assertIn("-only-testing:AteUITests/DuoExplorationUITests", workflow)
        selector = (ROOT / "scripts/select-ios-simulator.py").read_text()
        self.assertIn('EXPECTED_DEVICE = "iPhone 18 Pro"', selector)
        self.assertIn('EXPECTED_RUNTIME = "iOS-27-0"', selector)

class DuoCaptureVerdictTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("verify_duo", ROOT / "scripts/verify-duo-capture.py")
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
    def test_all_cases_must_pass(self):
        log = "\n".join(f"Test Case '-[AteUITests.DuoExplorationUITests {name}]' passed (20 seconds)." for name in self.module.CASES)
        self.assertTrue(self.module.verify(log))
        self.assertFalse(self.module.verify(log.replace("testRootPortraitAndLandscape]' passed", "testRootPortraitAndLandscape]' skipped")))
    def test_empty_or_summary_success_insufficient(self):
        self.assertFalse(self.module.verify("** TEST SUCCEEDED **"))
