"""Strict exploratory Duo selection; never changes the normal gate selector."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("duo", Path(__file__).resolve().parents[1] / "select-duo-simulator.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DuoSelectorTests(unittest.TestCase):
    def test_exact_duo_runtime(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-1": [{"name": "iPhone Duo", "udid": "duo", "isAvailable": True}]}
        self.assertEqual(module.select_device(devices), "duo")
    def test_no_fallback_to_gate_or_wrong_runtime(self):
        devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone Duo", "udid": "wrong"}], "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [{"name": "iPhone 18 Pro", "udid": "gate"}]}
        self.assertIsNone(module.select_device(devices))
    def test_unavailable_duo_fails(self):
        self.assertIsNone(module.select_device({"iOS-27-1": [{"name": "iPhone Duo", "udid": "no", "isAvailable": False}]}))
