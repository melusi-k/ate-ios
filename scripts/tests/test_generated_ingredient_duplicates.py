from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class GeneratedIngredientDuplicateTests(unittest.TestCase):
    def test_nonblocking_normalizer_is_generated_only_exact_equality_before_sanitizing(self):
        text = (ROOT / 'Ate/Logic/RecipeLogic.swift').read_text()
        normalization = text.split('static func normalize(', 1)[1].split('/// P0 duplicate-save', 1)[0]
        self.assertIn('if RecipeQuality.isGenerated(c)', normalization)
        self.assertIn('Set<Ingredient>()', normalization)
        self.assertIn('seen.insert($0).inserted', normalization)
        self.assertLess(normalization.index('seen.insert'), normalization.index('if !i.quantity.isFinite'))
        self.assertNotIn('quantity +=', normalization)

    def test_guidance_retains_example_and_no_new_order_gate(self):
        prompt = (ROOT / 'Ate/Logic/RecipePrompt.swift').read_text()
        self.assertIn('put that boil/drain before the fry', prompt)
        self.assertIn('Do not impose pre-boiling', prompt)
        self.assertIn('do not add repeated serve/rest/serve filler', prompt)
        native = (ROOT / 'AteTests/GeneratedIngredientDuplicateTests.swift').read_text()
        for term in ['for coating', 'for glazing', '.manual, .jsonLD, .imported',
                     'No automatic semantic reorder or deletion', 'Step 4', 'doneness cue']:
            self.assertIn(term, native)
