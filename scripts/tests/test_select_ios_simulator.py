"""Tests for the strict CI simulator selector."""

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "select-ios-simulator.py"
SPEC = importlib.util.spec_from_file_location("select_ios_simulator", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
select_device = MODULE.select_device


class SelectIOSSimulatorTests(unittest.TestCase):
    def test_selects_iphone_18_pro_on_ios_27_0(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18 Pro", "udid": "18PRO-UDID", "isAvailable": True},
                {"name": "iPhone 17", "udid": "17-UDID", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
                {"name": "iPhone 18 Pro", "udid": "WRONG-RUNTIME", "isAvailable": True},
            ],
        }
        self.assertEqual(select_device(devices), "18PRO-UDID")

    def test_does_not_fall_back_to_an_older_iphone(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 17 Pro", "udid": "17PRO-UDID", "isAvailable": True},
            ],
        }
        self.assertIsNone(select_device(devices))

    def test_ignores_unavailable_iphone_18_pro(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18 Pro", "udid": "UNAVAILABLE", "isAvailable": False},
            ],
        }
        self.assertIsNone(select_device(devices))


if __name__ == "__main__":
    unittest.main()
