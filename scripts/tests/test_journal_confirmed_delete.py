"""Static state and strict UI assertion preservation, not native execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
class ConfirmedDeleteTests(unittest.TestCase):
    def test_stable_owner_and_commit_before_dismissal(self):
        s = (ROOT / 'Ate/Views/JournalViews.swift').read_text()
        self.assertIn('.navigationTitle("Journal entry")\n        // The confirmation', s)
        self.assertIn('.accessibilityIdentifier("journal.delete.confirm")', s)
        d = s.split('private func deleteConfirmedEntry()', 1)[1].split('private func reloadEntry()', 1)[0]
        self.assertLess(d.index('deleteReflection(id: entryID)'), d.index('entry = nil'))
        self.assertLess(d.index('entry = nil'), d.index('store.journalRevision += 1'))
        self.assertLess(d.index('dismiss()'), d.index('store.journalRevision += 1'))
        self.assertIn('deleteProblem =', d)
    def test_original_destructive_assertions_remain(self):
        s = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        m = s.split('func testManualReflectionEditSaveCancelAndConfirmedDelete()', 1)[1].split('func testConfirmedDeleteFailure', 1)[0]
        for t in ['Cancel must keep the reflection', 'waitUntilGone(detail)', 'wait(app.navigationBars["Journal"])',
                  'Confirmed deletion must remove the created reflection from history']:
            self.assertIn(t, m)
        self.assertIn('confirmButton.tap()', m)
        self.assertIn('timeout: 10', s.split('private func waitUntilGone', 1)[1].split('private func any', 1)[0])
