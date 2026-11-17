from approved_merge_539 import normalize
"""The sync harness seeds the production model, never the legacy test model."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class UserDataSyncModelQualificationTests(unittest.TestCase):
    def test_harness_uses_production_journal_initializer(self):
        source = normalize('source:AteTests/UserDataSyncTests.swift', (ROOT / 'AteTests/UserDataSyncTests.swift').read_text())
        helper = source.split('private func seedJournal(',1)[1].split('\n    private func ',1)[0]
        self.assertIn('context.insert(Ate.JournalEntry(id: id,', helper)
        self.assertIn('prompt: "", text: text, state: nil, recipeIDs: []', helper)
        self.assertIn('try context.save()', helper)
        self.assertNotIn('stateRaw:', helper)
        legacy = normalize('source:AteTests/LegacyJournalStoreUpgradeTests.swift', (ROOT / 'AteTests/LegacyJournalStoreUpgradeTests.swift').read_text())
        self.assertIn('final class JournalEntry', legacy)
        self.assertIn('stateRaw: String', legacy)

    def test_all_sync_model_sites_are_production_and_rest_reconstructs(self):
        import re, hashlib
        source=normalize('source:AteTests/UserDataSyncTests.swift', (ROOT/'AteTests/UserDataSyncTests.swift').read_text())
        self.assertNotRegex(source,r'(?<!Ate\.)\bJournalEntry\b')
        self.assertEqual(source.count('FetchDescriptor<Ate.JournalEntry>'),3)
        self.assertEqual(source.count('ModelContainer(for: Ate.JournalEntry.self'),2)
        restored=restore_sync_model_qualification(source)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),BASE_SHA256)

BASE_SHA256='0edda4079b6019b6820d88513e1a8d73ffd644d285b127c7531c264772d77e66'
def restore_sync_model_qualification(source):
    return source.replace('FetchDescriptor<Ate.JournalEntry>', 'FetchDescriptor<JournalEntry>').replace('ModelContainer(for: Ate.JournalEntry.self', 'ModelContainer(for: JournalEntry.self')
