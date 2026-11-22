"""Journal UI must not inherit a terminated unit host; coverage stays blocking."""
from pathlib import Path
import hashlib
import importlib.util
import re
import unittest
import yaml
from journal_ui_host_handoff_delta import contract, restore
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('journal_required_native', ROOT / 'scripts/verify-full-unit-required.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)

class JournalUIHostHandoffTests(unittest.TestCase):
    def test_exact_inverse_and_protected_native_bodies(self):
        for path, c in contract()['files'].items():
            source = (ROOT / path).read_text()
            old = restore(path, source)
            self.assertEqual(hashlib.sha256(old.encode()).hexdigest(), c['parent_sha256'])
            self.assertEqual(restore(path, old), old)
            for mutant in [source + '# unrelated', source[:-1]]:
                with self.assertRaises(AssertionError):
                    restore(path, mutant)
        for path, digest in contract()['protected_sha256'].items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)

    def test_journal_changes_only_the_duplicate_unit_selector(self):
        path = '.github/workflows/journal-open-state-ui.yml'
        current = (ROOT / path).read_text()
        old = restore(path, current)
        scrub = lambda s: '\n'.join(line for line in s.splitlines() if not line.strip().startswith('#') and '-only-testing:AteTests/JournalReflectionEditTests' not in line and '"JournalReflectionEditTests test' not in line)
        self.assertEqual(scrub(current), scrub(old))
        main = current.split('- name: Journal open state app-launch UI tests', 1)[1].split('      - name:', 1)[0]
        selected = re.findall(r'-only-testing:([^\s\\]+)', main)
        self.assertEqual(selected, ['AteUITests/JournalOpenStateUITests', 'AteUITests/CanonicalUpgradeUITests'])
        self.assertNotRegex(main, r'-only-testing:AteTests(?:/|\s)')
        self.assertNotIn('\"JournalReflectionEditTests test', main)
        self.assertIn("JournalOpenStateUITests testReflectionEditFailureRetainsDraftThenRetryCommitsAndRefreshesHistory]' passed", main)
        self.assertEqual(yaml.safe_load(current)['jobs'].keys(), yaml.safe_load(old)['jobs'].keys())
        # Existing native body, skips, budgets, status, gate and artifact paths are exact.
        for token in ['-skip-testing:', 'timeout-minutes:', 'xcodebuild test-without-building', 'exit 1', 'resultBundlePath']:
            self.assertEqual(current.count(token), old.count(token), token)

    def test_both_journal_unit_cases_are_required_in_full_suite(self):
        c = contract()
        path = 'scripts/full-unit-required.txt'
        current = (ROOT / path).read_text()
        old = restore(path, current)
        self.assertEqual(current, old + '\n'.join(c['required']) + '\n')
        self.assertEqual(len(current.splitlines()), len(set(current.splitlines())))
        full = (ROOT / '.github/workflows/compile-check.yml').read_text().split('- name: Full exact-head unit suite', 1)[1].split('- name: Retain full unit diagnostics', 1)[0]
        self.assertIn('-only-testing:AteTests', full)
        self.assertNotIn('-skip-testing:', full)
        self.assertNotIn('continue-on-error', full)
        self.assertIn('python3 scripts/verify-full-unit-required.py full-unit-tests.json scripts/full-unit-required.txt', full)
        native = (ROOT / 'AteTests/JournalReflectionEditTests.swift').read_text()
        for identity in c['required']:
            self.assertIn('func ' + identity.split('/')[1] + '(', native)

    def test_real_native_verifier_rejects_missing_skipped_or_failed_moved_case(self):
        expected = contract()['required']
        make = lambda: {'testNodes': [{'nodeType': 'Test Case', 'nodeIdentifier': name + '()', 'result': 'Passed'} for name in expected]}
        self.assertEqual(verifier.validate(make(), expected), sorted(expected))
        for index in range(2):
            missing = make(); missing['testNodes'].pop(index)
            with self.assertRaises(ValueError): verifier.validate(missing, expected)
            for result in ['Skipped', 'Failed', 'Unknown', None]:
                bad = make(); bad['testNodes'][index]['result'] = result
                with self.assertRaises(ValueError): verifier.validate(bad, expected)

    def test_old_mixed_selection_or_lost_coverage_mutants_fail_pin(self):
        path = '.github/workflows/journal-open-state-ui.yml'
        source = (ROOT / path).read_text()
        mixed = source.replace('-only-testing:AteUITests/CanonicalUpgradeUITests', '-only-testing:AteTests/JournalReflectionEditTests \\\n            -only-testing:AteUITests/CanonicalUpgradeUITests', 1)
        with self.assertRaises(AssertionError): restore(path, mixed)
        path = 'scripts/full-unit-required.txt'; source = (ROOT / path).read_text()
        for identity in contract()['required']:
            with self.assertRaises(AssertionError): restore(path, source.replace(identity + '\n', '', 1))
