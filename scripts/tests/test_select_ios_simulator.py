"""Tests for the strict CI simulator selector."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from select_ios_simulator import select_device


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
