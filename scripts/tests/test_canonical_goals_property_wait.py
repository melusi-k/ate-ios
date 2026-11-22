"""Same-property, same-cap observation candidate. Not native qualification."""
from pathlib import Path
import hashlib
import re
import unittest
from canonical_goals_property_wait_delta import contract, restore
ROOT = Path(__file__).resolve().parents[2]
PATH = 'AteUITests/CanonicalUpgradeUITests.swift'

class CanonicalGoalsPropertyWaitTests(unittest.TestCase):
    def test_exact_inverse_is_idempotent_and_rejects_unrelated_changes(self):
        for path, entry in contract()['files'].items():
            source = (ROOT / path).read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), entry['current_sha256'])
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old).hexdigest(), entry['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            self.assertEqual(restore(path, source.decode()), old.decode())
            for mutant in [source + b'// unrelated', source[:-1]]:
                with self.assertRaises(AssertionError): restore(path, mutant)

    def test_entire_real_ui_journey_outside_the_two_line_wait_is_identical(self):
        current = (ROOT / PATH).read_text()
        old = restore(PATH, current)
        fragment = contract()['files'][PATH]['fragments'][0]
        self.assertEqual(current.replace(fragment['new'], '', 1), old.replace(fragment['old'], '', 1))
        self.assertEqual(fragment['old'].count('\n'), 2)
        self.assertEqual(current.count('func test'), old.count('func test'))
        self.assertEqual(re.findall(r'XCTAssert[^\n]+', current.replace(fragment['new'], '')),
                         re.findall(r'XCTAssert[^\n]+', old.replace(fragment['old'], '')))

    def test_same_enabled_property_true_value_and_exact_five_second_cap(self):
        fragment = contract()['files'][PATH]['fragments'][0]['new']
        self.assertIn('let ready = enabled.wait(for: \\.isEnabled, toEqual: true, timeout: 5)', fragment)
        self.assertIn('XCTAssertTrue(ready,', fragment)
        self.assertEqual(fragment.count('enabled.wait('), 1)
        for token in ['firstMatch', 'sleep(', 'try?', 'waitForExistence(', '.snapshot(', 'RunLoop', 'Task', 'DispatchQueue']:
            self.assertNotIn(token, fragment)
        source = (ROOT / PATH).read_text()
        self.assertIn('let enabled = app.switches["nutritionGoals.enabled.energy"]', source)
        self.assertIn('XCTAssertTrue(enabled.waitForExistence(timeout: 10))', source)
        self.assertIn('XCTAssertEqual(enabled.value as? String, "0",', source)
        self.assertIn('XCTAssertFalse(energy.exists)', source)

    def test_diagnostics_observe_the_single_result_and_screenshot_only_on_failure(self):
        fragment = contract()['files'][PATH]['fragments'][0]['new']
        self.assertEqual(fragment.count('ProcessInfo.processInfo.systemUptime'), 2)
        self.assertIn('GOALS-ENABLED-WAIT begin timeout=5', fragment)
        self.assertIn('GOALS-ENABLED-WAIT end result=', fragment)
        self.assertIn('elapsed_s=', fragment)
        self.assertIn('if !ready { shot("upgrade-goals-enabled-wait-failed") }', fragment)
        self.assertLess(fragment.index('enabled.wait('), fragment.index('if !ready'))
        self.assertLess(fragment.index('if !ready'), fragment.index('XCTAssertTrue(ready'))
        self.assertEqual(fragment.count('enabled.'), 1)
        self.assertNotIn('ready = true', fragment)

    def test_existing_workflows_native_cases_and_historical_json_pins_are_unchanged(self):
        for path, digest in contract()['protected_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)
        self.assertEqual(contract()['expected_native_counts'], {'Journal': 27, 'AteTests': 1354})

    def test_weakened_or_extended_gate_mutants_are_rejected(self):
        source = (ROOT / PATH).read_text()
        for old, new in [('toEqual: true, timeout: 5', 'toEqual: true, timeout: 10'),
                         ('\\.isEnabled, toEqual: true', '\\.isEnabled, toEqual: false'),
                         ('\\.isEnabled, toEqual: true', '\\.isHittable, toEqual: true'),
                         ('XCTAssertTrue(ready,', 'XCTAssertTrue(true,'),
                         ('if !ready { shot(', 'if ready { shot(')]:
            self.assertIn(old, source)
            with self.assertRaises(AssertionError): restore(PATH, source.replace(old, new, 1))
