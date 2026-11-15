from pathlib import Path
import subprocess, unittest
ROOT=Path(__file__).resolve().parents[2]
BASE='804855f7e3789a02b92109cf1a8a033824c09f5e'
class AddSheetIdentityTests(unittest.TestCase):
    def original(self,path):
        return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT,text=True)
    def test_only_identifier_added_to_product(self):
        path='Ate/Views/AddRecipeSheet.swift'
        source=(ROOT/path).read_text()
        extra='        .accessibilityIdentifier("addRecipe.content")\n'
        self.assertEqual(source.count(extra),1)
        self.assertEqual(source.replace(extra,'',1),self.original(path))
    def test_exact_heading_and_nav_contract_preserved_without_containing_query(self):
        path='AteUITests/CookIngredientsUITests.swift'
        source=(ROOT/path).read_text()
        direct='app.scrollViews["addRecipe.content"]'
        self.assertEqual(source.count(direct),1)
        self.assertNotIn('scrollViews.containing(.textField',source)
        restored=source.replace(direct,'app.scrollViews.containing(.textField, identifier: "linkField").firstMatch',1)
        self.assertEqual(restored,self.original(path))
