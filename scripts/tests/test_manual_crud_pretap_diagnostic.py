"""Row-scoped evidence does not replace original CRUD query or native actions."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class ManualCRUDPretapDiagnosticTests(unittest.TestCase):
    def test_original_query_and_assertions_follow_scoped_evidence(self):
        source = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        body = source.split('func testManualReflectionEditSaveCancelAndConfirmedDelete()', 1)[1].split('\n    func ', 1)[0]
        self.assertIn('let saved = app.descendants(matching: .any).matching(identifier: "journal.entry")', body)
        self.assertIn('.matching(NSPredicate(format: "label CONTAINS %@", original)).firstMatch', body)
        self.assertIn('XCTAttachment(string: saved.debugDescription)', body)
        self.assertNotIn('XCTAttachment(string: app.debugDescription)', body)
        self.assertLess(body.index('wait(saved)'), body.index('shot("manual-crud-created-row-before-tap")'))
        self.assertLess(body.index('add(rowEvidence)'), body.index('saved.tap()'))
        self.assertIn('XCTAssertEqual(detail.label, original, "Only the newly created reflection may be edited or deleted")', body)
