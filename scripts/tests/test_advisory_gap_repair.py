from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]
STEP = (ROOT / 'Ate/Logic/GeneratedStepQuality.swift').read_text()
QUALITY = (ROOT / 'Ate/Logic/RecipeQuality.swift').read_text()
BACKEND = (ROOT / 'Ate/Services/OnDeviceBackend.swift').read_text()

BACKEND_ADDITION = '''        let gaps = RecipeQuality.shortfall(card, labels: visibleLabels) + (fidelity?.issues(card) ?? [])
        // Advisory-only gap lists (unused implicit staples: oil/salt/pepper/water
        // listed but never used) skip the automatic repair pass. The review card still
        // lists them with a manual Repair option. An unused main ingredient and any
        // real gap repair exactly as before.
        if request.mode != .rewrite, !RecipeQuality.gapsNeedingRepair(gaps).isEmpty {
'''
BACKEND_ORIGINAL = '''        let gaps = RecipeQuality.shortfall(card, labels: visibleLabels) + (fidelity?.issues(card) ?? [])
        if request.mode != .rewrite, !gaps.isEmpty {
'''

def restore_advisory_gap_partition(test, s):
    """Exact inverse of the advisory-gap repair partition (post-#580 layer)."""
    test.assertEqual(s.count(BACKEND_ADDITION), 1)
    return s.replace(BACKEND_ADDITION, BACKEND_ORIGINAL, 1)

class AdvisoryGapRepairContracts(unittest.TestCase):
    def test_producer_and_classifier_share_one_suffix_constant(self):
        self.assertIn('static let unusedIngredientGapSuffix = "it is listed but never used in the steps."', STEP)
        self.assertIn('gaps.append("Explain when to use \\(ingredient.name); \\(unusedIngredientGapSuffix)")', STEP)
        self.assertIn('static func isImplicitStapleGap(_ gap: String) -> Bool {', STEP)
        # Closed exact-name list (packet A r3): flour, sugar and butter are NOT
        # advisory; compounds beyond the list (extra virgin olive oil) are not either.
        self.assertIn('static let implicitStaples: Set<String> = ["salt", "black pepper", "pepper", "water",\n                                               "cooking oil", "oil", "olive oil",\n                                               "vegetable oil", "sunflower oil"]', STEP)
        self.assertIn('return implicitStaples.contains(normalized)', STEP)
        # The literal sentence exists exactly once in the product sources.
        count = STEP.count('it is listed but never used in the steps.')
        self.assertEqual(count, 1, 'gap text must come from the shared constant only')

    def test_automatic_repair_routes_through_the_partition(self):
        self.assertIn('if request.mode != .rewrite, !RecipeQuality.gapsNeedingRepair(gaps).isEmpty {', BACKEND)
        self.assertIn('static func gapsNeedingRepair(_ gaps: [String]) -> [String]', QUALITY)
        self.assertIn('gaps.filter { !GeneratedStepQuality.isImplicitStapleGap($0) }', QUALITY)

    def test_review_card_visibility_is_preserved(self):
        # shortfall and issues keep returning every gap: the user still sees the
        # advisory items and the manual Repair button; only the automatic pass narrows.
        shortfall = QUALITY.split('static func shortfall', 1)[1].split('    }\n', 1)[0]
        self.assertNotIn('gapsNeedingRepair', shortfall)
        issues = QUALITY.split('static func issues', 1)[1]
        self.assertIn('out += GeneratedStepQuality.issues(c)', issues)

    def test_repair_instruction_still_receives_the_full_gap_list(self):
        # When a real gap triggers the pass, the repair fixes everything listed,
        # advisory items included.
        self.assertIn('RecipePrompt.retryInstruction(gaps: gaps, visibleLabels: visibleLabels)', BACKEND)

    def test_no_timeout_or_allowance_changes(self):
        self.assertNotIn('timeout', BACKEND.split('gapsNeedingRepair', 1)[1][:400].lower())

if __name__ == '__main__':
    unittest.main()
