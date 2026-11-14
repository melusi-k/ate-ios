from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RepairFeedbackTests(unittest.TestCase):
    def test_status_is_outside_needs_input_panel_and_scrolls_into_view(self):
        text = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        panel = text.split('if let d = draft, RecipeQuality.needsInput(d)', 1)[1].split('if let d = draft, RecipeQuality.isGenerated(d)', 1)[0]
        self.assertNotIn('if let repairError', panel)
        self.assertNotIn('if let repairResult', panel)
        for term in ['ScrollViewReader', 'reader.scrollTo("repairStatusAnchor"',
                     'RepairFeedback.accepted(original: original, repaired: repaired)',
                     'repairConfidenceExplanation', 'repairStatusRevision += 1']:
            self.assertIn(term, text)

    def test_sixty_second_deadlines_close_admission_not_structured_wait_races(self):
        repair = (ROOT / 'Ate/Logic/DraftRepairAttempt.swift').read_text()
        generation = (ROOT / 'Ate/Logic/DraftGenerationAttempt.swift').read_text()
        for text in [repair, generation]:
            self.assertIn('60_000_000_000', text)
            self.assertIn('deadline?.cancel()', text)
            self.assertNotIn('withTaskGroup', text)
        timeout = repair.split('// Close admission', 1)[1].split('task = Task', 1)[0]
        self.assertLess(timeout.index('self.token = nil'), timeout.index('failed(BackendError'))
        self.assertIn('self.invalidate()\n            timedOut()', generation)

    def test_confidence_and_strict_repair_contract_remain(self):
        repair = (ROOT / 'Ate/Logic/RecipeDraftRepair.swift').read_text()
        self.assertIn('repaired.aiConfidence = original.aiConfidence', repair)
        self.assertIn('newGaps.isStrictSubset(of: oldGaps)', repair)
        native = (ROOT / 'AteTests/RepairFeedbackTests.swift').read_text()
        for term in ['backend.complete()', 'effects, 0', 'finishes, 1', 'repaired.aiConfidence, 0.7']:
            self.assertIn(term, native)
