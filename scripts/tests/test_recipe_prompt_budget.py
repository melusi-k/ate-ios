"""Cheap source preflight, not a replacement for native Swift String/XCTest checks."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'Ate/Logic/RecipePrompt.swift').read_text()
SHARED = '\n'.join(line[4:] for line in SOURCE.split('static let instructions = """\n', 1)[1].split('\n    """', 1)[0].splitlines())

class RecipePromptBudgetContracts(unittest.TestCase):
    def test_shared_and_mode_budgets_remain_original_limits(self):
        self.assertLessEqual(len(SHARED), 3450)
        for mode in ['link', 'social', 'photo', 'screenshot', 'prompt']:
            brief = re.search(r'case \.' + mode + r': brief = "([^"\n]*)"', SOURCE).group(1)
            self.assertLessEqual(len(SHARED + '\n' + brief), 3900, mode)

    def test_all_protein_guarantees_remain_explicit(self):
        for phrase in ['source protein species/cut', 'pork ribs, pork belly, bacon, pork chops',
                       'beef ribs, chicken wings', 'never relabel beef/lamb ribs as pork',
                       'Keep source amounts', 'do not guess weights for counted pieces',
                       'generated mixed proteins', 'list primary first by largest comparable quantity',
                       'Library categories come from ingredients, not invented tags']:
            self.assertIn(phrase, SHARED)

    def test_existing_safety_quality_rules_and_examples_remain(self):
        for phrase in ['Never use place names', 'hashtags', '@handles', 'NAMED dish',
                       'Unknown dish', 'confidence below 0.2', 'metric', 'tripe takes 2 to 3 h',
                       'at least 4 real ingredients', 'doneness', 'timeMinutes = step sum + prep',
                       'Prep: N min', 'salt, oil, water, bread, wrappers and filling',
                       'aromatics/spices precede simmering', 'pre-boil liquid handling',
                       'Preserve source order', "flag gaps, don't invent missing source facts",
                       'Example 1', 'Example 2']:
            self.assertIn(phrase, SHARED)
        for phrase in ['First identify the dish', 'confidence below 0.2',
                       'Do not invent a different dish', 'call lookupRegionalDish']:
            self.assertEqual(SHARED.count(phrase), 1)
