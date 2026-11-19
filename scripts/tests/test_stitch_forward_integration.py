"""Reviewed runtime/test bytes stay exact across screen integration."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from stitch_cook_delta import restore as restore_cook
from stitch_detail_delta import restore as restore_detail
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
        for cls in ['LibrarySelectionUITests', 'AddRecipeScanUITests', 'StitchRecipeDetailUITests', 'StitchCookModeUITests']:
            self.assertIn('-only-testing:AteUITests/' + cls, workflow)
            ui = (ROOT / ('AteUITests/' + cls + '.swift')).read_text()
            for method in re.findall(r'    func (test\w+)\(', ui): self.assertIn(method, workflow)
        self.assertIn('LibrarySelectionUITests $test', workflow)
        self.assertIn('AddRecipeScanUITests $test', workflow)
    def test_inverse_order_restores_exact_published_parent_then_historical_base(self):
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        detail_parent = restore_cook('main:.github/workflows/compile-check.yml', workflow)
        scan_parent = restore_detail('main:.github/workflows/compile-check.yml', detail_parent)
        published = restore_scan('main:.github/workflows/compile-check.yml', scan_parent)
        contract = json.loads((ROOT / 'scripts/tests/add_recipe_scan_inverse.json').read_text())['.github/workflows/compile-check.yml']
        self.assertEqual(hashlib.sha256(published.encode()).hexdigest(), contract['parent_sha'])
        historic = restore_selection('main:.github/workflows/compile-check.yml', published)
        parent = json.loads((ROOT / 'scripts/tests/library_selection_inverse.json').read_text())['.github/workflows/compile-check.yml']
        self.assertEqual(hashlib.sha256(historic.encode()).hexdigest(), parent['parent_sha'])
        with self.assertRaises(AssertionError): restore_selection('main:.github/workflows/compile-check.yml', workflow)

    def test_reviewed_detail_bytes_are_exact(self):
        contracts = {'Ate/Logic/RecipeDetailMetadata.swift': '5c3b1b4f86156af0c0b33435af325c13ec2dc8019327b83a1e0b6eeec08c6adb', 'Ate/Views/Components.swift': '51a0a53e1bf1349b940722a6547f4ce59cdb829f7e47b53542c2fe4f816aae69', 'Ate/Views/RecipeDetailView.swift': 'ae1c55b3a4ae28629ab37eb56089079c94e1a0ee1a1f93232f7fec92a098c621', 'AteTests/RecipeDetailMetadataTests.swift': '4b1c4d6fbd1a9aaa7c48d61096266b7f21dac6e308a374050b69ad7ec776c5f2', 'AteUITests/StitchRecipeDetailUITests.swift': '981a1bd204fbf73905a4863106c0113ce5640d286fe3faa0c468687433c396b1'}
        for path, expected in contracts.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected, path)

    def test_reviewed_cook_bytes_are_exact(self):
        contracts = {'Ate/Logic/CookModeFeature.swift': 'e9bea1817f8d6a391045d67c52d4eda32fabf7f0e82ce4b2432227973f4d17cd', 'Ate/Views/CookModeView.swift': '2bdb192edd2c57a60a7704e405aee46dabe4a8e153b58b524234520aa2bec197', 'AteTests/CookModeFeatureTests.swift': 'be1128485d141f41018c56f218ab31e6729c56cb080b6aeeb356f569232a048f', 'AteUITests/StitchCookModeUITests.swift': '7e7a7371905d30f4c33959749a9c3a19be9a712eb372a16909aa6e462a5d044c'}
        for path, expected in contracts.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), expected, path)
