from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class BoundedReorderActions(unittest.TestCase):
    def test_selection_and_actions_both_selected_and_required(self):
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        first=s.split('func test29_ReorderMyOrder()',1)[1].split('func test29b_',1)[0]
        action=s.split('func test29b_ReorderMyOrderActions()',1)[1].split('func testFirstLibrary',1)[0]
        self.assertIn('pick("sortMenu", "My order")',first)
        self.assertIn('new (unordered) cards newest first',first)
        self.assertNotIn('Move up',first)
        self.assertIn('-qaSavedRecipesForReorderAction',action)
        for term in ['first.press(forDuration: 1.2)', 'wait(app.buttons["Move up"], 3)', 'app.buttons["Move up"].tap()', '"moved up"', 'thenDragTo: text("Second dish")', 'library-reorder-drag']:
            self.assertIn(term,action)
        for name in ['dogfood-qualification.yml','menu-qualification.yml']:
            workflow=(ROOT/'.github/workflows'/name).read_text()
            for method in ['test29_ReorderMyOrder','test29b_ReorderMyOrderActions']:
                self.assertIn('-only-testing:AteUITests/AteUITests/'+method,workflow)
            self.assertIn('test29b_ReorderMyOrderActions',workflow)
        fixture=(ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        for term in ['.sortIndex =','store.move','store.path']:
            self.assertNotIn(term,fixture)
