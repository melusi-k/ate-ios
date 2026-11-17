"""Tests for the strict CI simulator selector."""

import importlib.util
import contextlib
import io
import json
from unittest.mock import patch
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "select-ios-simulator.py"
SPEC = importlib.util.spec_from_file_location("select_ios_simulator", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
select_device = MODULE.select_device


class SelectIOSSimulatorTests(unittest.TestCase):
    def test_selects_newest_iphone_18_pro_on_ios_27x(self):
        devices = {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18 Pro", "udid": "18PRO-UDID", "isAvailable": True},
                {"name": "iPhone 17", "udid": "17-UDID", "isAvailable": True},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
                {"name": "iPhone 18 Pro", "udid": "NEWER-RUNTIME", "isAvailable": True},
            ],
        }
        self.assertEqual(select_device(devices), "NEWER-RUNTIME")

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

    def test_accepts_only_available_27x_on_the_exact_gate_device(self):
        for runtime in ['iOS-27-2', 'iOS-27-10-1']:
            self.assertEqual(select_device({runtime: [dict(name="iPhone 18 Pro", udid="gate", isAvailable=True)]}), "gate")
        for runtime in ['iOS-26-9', 'iOS-28-0', 'iOS-270-0', 'tvOS-27-2', 'iOS-27-2-beta', 'garbage.iOS-27-2']:
            self.assertIsNone(select_device({runtime: [dict(name="iPhone 18 Pro", udid="wrong", isAvailable=True)]}))
        self.assertIsNone(select_device({'iOS-27-2': [dict(name="iPhone Duo",udid="duo",isAvailable=True)]}))

    def test_numeric_newest_and_deterministic_udid_tie(self):
        devices = {r: [dict(name="iPhone 18 Pro",udid=u,isAvailable=True)]
                   for r,u in [('iOS-27-2','two'),('iOS-27-10','ten')]}
        devices['iOS-27-10'].append(dict(name="iPhone 18 Pro",udid="aaa",isAvailable=True))
        self.assertEqual(select_device(devices), 'aaa')
        self.assertEqual(select_device(dict(reversed(list(devices.items())))), 'aaa')

    def test_unavailable_newer_does_not_hide_available_gate(self):
        devices={'iOS-27-2':[dict(name="iPhone 18 Pro",udid="old",isAvailable=True)],
                 'iOS-27-3':[dict(name="iPhone 18 Pro",udid="new",isAvailable=False)]}
        self.assertEqual(select_device(devices),'old')

    def test_cli_reports_actual_runtime_and_keeps_stdout_udid_only(self):
        inventory={'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-2':
            [dict(name="iPhone 18 Pro",udid="gate",isAvailable=True)]}}
        out,err=io.StringIO(),io.StringIO()
        with patch.object(MODULE.subprocess,'run',return_value=type('Result',(),{'stdout':json.dumps(inventory)})()), contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
            self.assertEqual(MODULE.main(),0)
        self.assertEqual(out.getvalue(),'gate\n')
        self.assertIn('iOS-27-2',err.getvalue())
        self.assertNotIn('iOS 27.0',err.getvalue())

    def test_cli_fails_closed_with_no_qualifying_gate_device(self):
        out,err=io.StringIO(),io.StringIO()
        with patch.object(MODULE.subprocess,'run',return_value=type('Result',(),{'stdout':'{"devices": {}}'})()), contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
            self.assertEqual(MODULE.main(),1)
        self.assertEqual(out.getvalue(),'')
        self.assertIn('no fallback device',err.getvalue())


if __name__ == "__main__":
    unittest.main()
