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
        self.assertNotIn('.alert("Delete this journal entry?"', detail)
        self.assertEqual(detail.count("JournalDeleteConfirmation(isPresented: $confirmDelete"), 1)
        for action in ('journal.edit.cancel', 'journal.edit.save'):
            self.assertEqual(detail.count('.accessibilityIdentifier("' + action + '")'), 1)

    def test_native_action_identity_and_single_presenter(self):
        native = (ROOT / 'Ate/Views/JournalDeleteConfirmation.swift').read_text()
        for action in ('journal.delete.confirm', 'journal.delete.cancel'):
            self.assertEqual(native.count('accessibilityIdentifier = "' + action + '"'), 1)
        self.assertEqual(native.count('alert.addAction('), 2)
        self.assertIn('activeAlert == nil', native)
        self.assertIn('activeAlert = (token, alert)', native)
        self.assertIn('validToken == token && pendingDelete == token', native)
        self.assertIn('self?.completeDismiss(token: active.token)', native)
        self.assertIn('retired = true', native)
        self.assertNotIn('setValue(', native)
        self.assertNotIn('DispatchQueue', native)

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
