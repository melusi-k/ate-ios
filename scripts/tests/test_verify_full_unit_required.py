import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('full_unit_required', Path(__file__).parents[1] / 'verify-full-unit-required.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def tree(result='Passed', name='CookSessionTests/testScaledAmountsRenderForArbitraryFactor()'):
    return {'testNodes': [{'nodeType': 'Test Suite', 'children': [
        {'nodeType': 'Test Case', 'nodeIdentifier': name, 'result': result}]}]}


class FullUnitRequiredTests(unittest.TestCase):
    required = ['CookSessionTests/testScaledAmountsRenderForArbitraryFactor']

    def test_exact_native_pass_is_independent_of_interleaved_console(self):
        self.assertEqual(module.validate(tree(), self.required), self.required)

    def test_other_full_suite_cases_are_allowed(self):
        value = tree()
        value['testNodes'].append({'nodeType': 'Test Case', 'nodeIdentifier': 'Other/test()', 'result': 'Passed'})
        self.assertEqual(module.validate(value, self.required), self.required)

    def test_missing_refuses(self):
        with self.assertRaises(ValueError):
            module.validate(tree(name='Other/test'), self.required)

    def test_skipped_failed_and_unknown_refuse(self):
        for result in ['Skipped', 'Failed', None, 'Unknown']:
            with self.subTest(result=result), self.assertRaises(ValueError):
                module.validate(tree(result=result), self.required)

    def test_duplicate_case_refuses(self):
        value = tree()
        value['testNodes'] += value['testNodes'][:]
        with self.assertRaises(ValueError):
            module.validate(value, self.required)

    def test_malformed_tree_refuses(self):
        for value in [{}, {'testNodes': [None]}, {'testNodes': [{'children': None}]}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.validate(value, self.required)

    def test_empty_or_repeated_requirements_refuse(self):
        for required in [[], self.required * 2]:
            with self.assertRaises(ValueError):
                module.validate(tree(), required)
