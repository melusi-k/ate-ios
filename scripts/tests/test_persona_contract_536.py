"""Keep the native persona token and broader cuisine coverage together."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class PersonaContract536Tests(unittest.TestCase):
    def test_product_persona_satisfies_existing_native_contract(self):
        source = (ROOT / 'Ate/Logic/RecipePrompt.swift').read_text()
        instructions = source.split('static let instructions = """', 1)[1].split('"""', 1)[0]
        for token in ['South African home-cooking expert', 'Southern/West African', 'international', 'at least 4 real ingredients', '°C', 'Chakalaka', 'bake at 160°C', 'First identify the dish']:
            self.assertIn(token, instructions)
        native = (ROOT / 'AteTests/QualityAndDedupeTests.swift').read_text()
        self.assertIn('"South African home-cooking expert"', native)
