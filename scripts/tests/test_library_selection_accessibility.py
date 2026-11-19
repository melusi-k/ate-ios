"""Source/inverse checks only. Native accessibility still needs XCTest evidence."""
import hashlib
import json
from pathlib import Path
import unittest
from library_selection_accessibility_delta import restore

ROOT = Path(__file__).resolve().parents[2]

class LibrarySelectionAccessibilityTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'Ate/Views/LibraryView.swift').read_text()
        self.contract = json.loads((ROOT / 'scripts/tests/library_selection_accessibility_inverse.json').read_text())

    def test_explicit_native_text_button_replaces_card_accessibility(self):
        card = self.view.split('private func selectionCard', 1)[1].split('private var selectionSummary', 1)[0]
        self.assertIn('.accessibilityRepresentation {', card)
        self.assertIn('Button(recipe.title) { selection.toggle(recipe.id) }', card)
        self.assertIn('.accessibilityValue(selected ? "Selected" : "Not selected")', card)
        self.assertIn('.accessibilityIdentifier("library.selection.recipe.\\(recipe.id)")', card)
        self.assertNotIn('.accessibilityElement(children: .ignore)', card)

    def test_exact_repair_inverse_preserves_entire_reviewed_library(self):
        restored = restore('main:Ate/Views/LibraryView.swift', self.view)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), self.contract['parent_sha'])
        self.assertEqual(restore('main:Ate/Views/LibraryView.swift', self.view.encode()), restored.encode())
        self.assertEqual(restore('unrelated', self.view), self.view)

    def test_missing_changed_and_duplicated_repair_fail_closed(self):
        new = self.contract['new']
        for value in [self.view.replace(new, '', 1), self.view.replace('Button(recipe.title)', 'Button("Wrong")', 1), self.view + new]:
            with self.assertRaises(AssertionError):
                restore('main:Ate/Views/LibraryView.swift', value)
