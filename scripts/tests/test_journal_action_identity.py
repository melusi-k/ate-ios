"""Keep presentation ownership and every Journal action identity unambiguous."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class JournalActionIdentityTests(unittest.TestCase):
    def test_one_concrete_detail_owner_and_distinct_action_identifiers(self):
        source = (ROOT / 'Ate/Views/JournalViews.swift').read_text()
        detail = source.split('struct JournalEntryDetailView: View', 1)[1].split('private func deleteConfirmedEntry()', 1)[0]
        self.assertIn('VStack(spacing: 0) {\n            if let e = entry {', detail)
        self.assertNotIn('Group {\n            if let e = entry {', detail)
        self.assertEqual(detail.count('.alert("Delete this journal entry?"'), 1)
        for action in ('journal.edit.cancel', 'journal.edit.save', 'journal.delete.confirm', 'journal.delete.cancel'):
            self.assertEqual(detail.count('.accessibilityIdentifier("' + action + '")'), 1)

    def test_crud_and_retry_keep_exact_uniqueness_and_saved_state_assertions(self):
        source = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        self.assertIn('cancelConfirmation.buttons["journal.delete.cancel"].tap()', source)
        self.assertIn('XCTAssertEqual(cancelConfirmation.buttons.matching(identifier: "journal.delete.cancel").count, 1)', source)
        self.assertIn('XCTAssertEqual(confirmation.buttons.matching(identifier: "journal.delete.confirm").count, 1)', source)
        self.assertEqual(source.count('XCTAssertEqual(alert.buttons.matching(identifier: "journal.delete.confirm").count, 1)'), 2)
        self.assertIn('"Cancel must keep the reflection"', source)
        self.assertIn('"Only successful explicit retry may remove the target from history"', source)
        self.assertIn('"Confirmed deletion must commit and verify, not only dismiss an alert"', source)


if __name__ == '__main__':
    unittest.main()
