"""The sync harness seeds the production model, never the legacy test model."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class UserDataSyncModelQualificationTests(unittest.TestCase):
    def test_harness_uses_production_journal_initializer(self):
        source = (ROOT / 'AteTests/UserDataSyncTests.swift').read_text()
        helper = source.split('private func seedJournal(',1)[1].split('\n    private func ',1)[0]
        self.assertIn('context.insert(Ate.JournalEntry(id: id,', helper)
        self.assertIn('prompt: "", text: text, state: nil, recipeIDs: []', helper)
        self.assertIn('try context.save()', helper)
        self.assertNotIn('stateRaw:', helper)
        legacy = (ROOT / 'AteTests/LegacyJournalStoreUpgradeTests.swift').read_text()
        self.assertIn('final class JournalEntry', legacy)
        self.assertIn('stateRaw: String', legacy)
