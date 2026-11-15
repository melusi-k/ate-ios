"""Source guard for raw failed draft versus normalized committed edit."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class JournalEditRetryExpectationTests(unittest.TestCase):
    def test_retry_checks_both_exact_contracts(self):
        s = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        t = s.split('func testReflectionEditFailureRetainsDraftThenRetryCommitsAndRefreshesHistory()', 1)[1].split('func testManualReflectionEditSaveCancelAndConfirmedDelete()', 1)[0]
        for expected in ['try XCTUnwrap(editor.value as? String)',
                         'retainedDraft.trimmingCharacters(in: .whitespacesAndNewlines)',
                         'XCTAssertEqual(editor.value as? String, retainedDraft,',
                         'XCTAssertEqual(detail.label, committedText)',
                         'NSPredicate(format: "label CONTAINS %@", committedText)',
                         'XCTAssertNotEqual(committedText, original,',
                         'wait(any("journal.edit.error"))', 'waitUntilGone(editor)']:
            self.assertIn(expected, t)
        self.assertEqual(t.count('buttons["journal.edit.save"].tap()'), 2)
    def test_store_and_native_unit_already_require_trim(self):
        s = (ROOT / 'Ate/Services/JournalSuggestionService.swift').read_text()
        update = s.split('func update(_ entry:', 1)[1].split('func saveFromIntent', 1)[0]
        self.assertIn('let text = text.trimmingCharacters(in: .whitespacesAndNewlines)', update)
        u = (ROOT / 'AteTests/JournalReflectionEditTests.swift').read_text()
        self.assertIn('healthy.update(reader, text: "  Retained edit draft  ")', u)
        self.assertIn('XCTAssertEqual(reader.text, "Retained edit draft")', u)
