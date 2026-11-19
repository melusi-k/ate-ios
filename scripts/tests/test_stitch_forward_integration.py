"""Reviewed runtime/test bytes stay exact across screen integration."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from add_recipe_scan_delta import restore as restore_scan
from library_selection_delta import restore as restore_selection
ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = {'Ate/Views/LibraryView.swift': '3ea69957642cb8d4f27f9e086bb6a0b0196d0bcf03e50465f4f2da47de9d16d8', 'Ate/Logic/LibrarySelection.swift': '5ed1650da30d2a8a23bc18907cc1c1de2ddb772e2bcb729d3db01bbd9f79e05e', 'Ate/App/LibrarySelectionQAFixtures.swift': '91b93350e3a71b7222bd55ab851eb7c24074693f0e65478f408b2f67d681a28f', 'AteTests/LibrarySelectionTests.swift': '36833e62825aef6fc90545b23906f4d51c071a5d5709ac3c061b1027a3ce8ded', 'AteUITests/LibrarySelectionUITests.swift': 'a8a6c1a22ddd76ab52b7fe83266ccb63743781c5baa74e4d50dfa2642c77d71d', 'Ate/Views/AddRecipeSheet.swift': 'be13a6a290b2cd85b78641fa6909856304445a832a447053616b3cee561e4258', 'Ate/Logic/AddRecipeReviewSummary.swift': 'ebe04e97bd2f51a363f8503b2d12f10342b9b19733c355412ba462e6f27c21a5', 'AteTests/AddRecipeReviewSummaryTests.swift': 'f5e1ab0f10124bd0b8a93705976ba02accec4de590228b2974af110e710a6e95', 'AteUITests/AddRecipeScanUITests.swift': '14eb03943a53e348b44d930b29c7fd34484ec55557f82da26ee5382385165141'}

class StitchForwardIntegrationTests(unittest.TestCase):
    def test_reviewed_runtime_and_native_test_bytes_are_exact(self):
        for path, expected in CONTRACTS.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected, path)
    def test_both_ui_classes_and_each_named_method_are_retained(self):
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        for cls in ['LibrarySelectionUITests', 'AddRecipeScanUITests']:
            self.assertIn('-only-testing:AteUITests/' + cls, workflow)
            ui = (ROOT / ('AteUITests/' + cls + '.swift')).read_text()
            for method in re.findall(r'    func (test\w+)\(', ui): self.assertIn(method, workflow)
        self.assertIn('LibrarySelectionUITests $test', workflow)
        self.assertIn('AddRecipeScanUITests $test', workflow)
    def test_inverse_order_restores_exact_published_parent_then_historical_base(self):
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        published = restore_scan('main:.github/workflows/compile-check.yml', workflow)
        contract = json.loads((ROOT / 'scripts/tests/add_recipe_scan_inverse.json').read_text())['.github/workflows/compile-check.yml']
        self.assertEqual(hashlib.sha256(published.encode()).hexdigest(), contract['parent_sha'])
        historic = restore_selection('main:.github/workflows/compile-check.yml', published)
        parent = json.loads((ROOT / 'scripts/tests/library_selection_inverse.json').read_text())['.github/workflows/compile-check.yml']
        self.assertEqual(hashlib.sha256(historic.encode()).hexdigest(), parent['parent_sha'])
        with self.assertRaises(AssertionError): restore_selection('main:.github/workflows/compile-check.yml', workflow)
