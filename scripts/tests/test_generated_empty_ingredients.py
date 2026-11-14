from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class GeneratedEmptyIngredientContracts(unittest.TestCase):
    def test_empty_list_is_rejected_independent_of_known_food_vocabulary(self):
        quality = (ROOT / 'Ate/Logic/RecipeQuality.swift').read_text()
        generated = quality.split('if isGenerated(c) {', 1)[1]
        self.assertIn('if c.ingredients.isEmpty {', generated)
        self.assertIn('out.append("The generated recipe needs measured ingredients.")', generated)
        self.assertLess(generated.index('if c.ingredients.isEmpty'), generated.index('GeneratedStepQuality.issues'))
        tests = (ROOT / 'AteTests/RecipeDiscoveryTests.swift').read_text()
        for phrase in ['("mock", demo)', '("empty ingredients", incomplete)', '("confidence 0.4", uncertain)',
                       '("saved title", duplicate)', 'XCTAssertTrue(session.suggestions.isEmpty, label)',
                       'XCTAssertNotNil(session.message, label)', 'XCTAssertTrue(RecipeQuality.needsInput(empty))',
                       'XCTAssertFalse(RecipeQuality.needsInput(card())']:
            self.assertIn(phrase, tests)
