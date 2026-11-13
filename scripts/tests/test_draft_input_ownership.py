"""Source wiring guard only; native delayed-load behavior lives in XCTest."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class DraftInputOwnershipTests(unittest.TestCase):
    def test_picker_loads_are_owned_and_cover_checks_selected_recipe(self):
        source = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('photoInputAttempt.start(load:', source)
        self.assertIn('coverInputAttempt.start(load:', source)
        self.assertIn('guard let recipeID, draft?.id == recipeID, !saving,', source)
        self.assertNotIn('Task { imageData = try? await item?', source)

    def test_terminal_actions_invalidate_before_persistent_or_external_effects(self):
        source = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        discard = source.split('Button("Discard", role: .destructive)', 1)[1].split('Button("Keep editing"', 1)[0]
        self.assertLess(discard.index('invalidateInputLoads()'), discard.index('store.drafts.clear()'))
        save = source.split('Button(saving ? "Saving…"', 1)[1].split('.buttonStyle', 1)[0]
        self.assertLess(save.index('invalidateInputLoads()'), save.index('onSave('))
        start = source.split('private func startGeneration()', 1)[1].split('private func generate(', 1)[0]
        self.assertLess(start.index('invalidateInputLoads()'), start.index('generationAttempt.start'))
        helper = (ROOT / 'Ate/Logic/DraftInputAttempt.swift').read_text()
        self.assertLess(helper.index('self.token == value, !Task.isCancelled'), helper.index('apply(result)'))
