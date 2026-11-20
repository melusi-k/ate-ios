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
        for phrase in ['("mock", demo)', '("neither ingredients nor cooking steps", incomplete)', 'XCTAssertEqual(editable.suggestions.first?.aiConfidence, 0.4)',
                       '("saved title", duplicate)', 'XCTAssertTrue(session.suggestions.isEmpty, label)',
                       'XCTAssertNotNil(session.message, label)', 'XCTAssertTrue(RecipeQuality.needsInput(empty))',
                       'XCTAssertFalse(RecipeQuality.needsInput(card())']:
            self.assertIn(phrase, tests)

    def test_negative_fixture_has_neither_content_but_steps_only_positive_remains(self):
        source=(ROOT/'AteTests/RecipeDiscoveryTests.swift').read_text()
        self.assertIn('var incomplete = card(); incomplete.ingredients = []; incomplete.steps = []',source)
        self.assertIn('var uncertain = card(); uncertain.aiConfidence = 0.4',source)
        positive=(ROOT/'AteTests/RecipeContentAdmissionTests.swift').read_text()
        self.assertIn('func testExploreStepsOnlyFoodIsEditableAndCanBeExplicitlySaved()',positive)
