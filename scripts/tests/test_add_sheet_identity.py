from pathlib import Path
import hashlib, unittest
ROOT=Path(__file__).resolve().parents[2]
# Entire original files at 804855f7e3789a02b92109cf1a8a033824c09f5e.
BASE_SHA256 = {
    'Ate/Views/AddRecipeSheet.swift': '883ba15cdc99ba9c7de5c00f9db0f1227f6cf459829f268ef09246a674594282',
    'AteUITests/CookIngredientsUITests.swift': '739ca37c05e1dd7f4cc40f07dcca2618c26da9f14e605a10dbe4899f001a3b5c',
}
class AddSheetIdentityTests(unittest.TestCase):
    def test_only_identifier_added_to_product(self):
        path='Ate/Views/AddRecipeSheet.swift'
        source=(ROOT/path).read_text()
        extra='        .accessibilityIdentifier("addRecipe.content")\n'
        self.assertEqual(source.count(extra),1)
        self.assertEqual(hashlib.sha256(source.replace(extra,'',1).encode()).hexdigest(),BASE_SHA256[path])
    def test_exact_heading_and_nav_contract_preserved_without_containing_query(self):
        path='AteUITests/CookIngredientsUITests.swift'
        source=(ROOT/path).read_text()
        direct='app.scrollViews["addRecipe.content"]'
        self.assertEqual(source.count(direct),1)
        self.assertNotIn('scrollViews.containing(.textField',source)
        restored=source.replace(direct,'app.scrollViews.containing(.textField, identifier: "linkField").firstMatch',1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),BASE_SHA256[path])
