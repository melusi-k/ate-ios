"""Source preflight, not a substitute for the unchanged native F1/size guards."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SourcePreparationPromptBudget(unittest.TestCase):
    def test_shared_and_per_mode_lengths_with_original_caps(self):
        text = (ROOT / 'Ate/Logic/RecipePrompt.swift').read_text()
        block = text.split('static let instructions = """\n', 1)[1].split('\n    """', 1)[0]
        shared = '\n'.join(line[4:] for line in block.splitlines())
        self.assertLessEqual(len(shared), 3450)
        for mode, brief in re.findall(r'case \.(link|social|photo|screenshot|prompt): brief = "([^"\n]*)"', text):
            self.assertLessEqual(len(shared) + 1 + len(brief), 3900, mode)
        for phrase in ['put that boil/drain before the fry', 'Do not impose pre-boiling where unneeded',
                       'Finish cooking and any stated rest before serving', 'do not add repeated serve/rest/serve filler',
                       'distinct coating/glaze uses separate', 'no identical ingredient rows']:
            self.assertIn(phrase, shared)

    def test_source_only_boundary_keeps_default_and_generated_normalization(self):
        parser = (ROOT / 'Ate/Logic/JSONLD.swift').read_text()
        source = (ROOT / 'Ate/Logic/SourceRecipeFidelity.swift').read_text()
        self.assertIn('static func parse(_ raw: String) -> Ingredient', parser)
        self.assertIn('parse(raw, preserveSourceName: false)', parser)
        self.assertIn('if !preserveSourceName {', parser)
        self.assertIn('parts.map { IngredientParser.parse($0, preserveSourceName: true) }', source)
        self.assertIn('c.ingredients.map(IngredientFieldNormalization.normalizeGenerated)', (ROOT / 'Ate/Logic/RecipeLogic.swift').read_text())
        native = (ROOT / 'AteTests/SourcePreparationBoundaryTests.swift').read_text()
        self.assertIn('contract.issues(normalized).isEmpty', native)
        self.assertIn('IngredientParser.parse("1 onion diced")', native)
