"""Only replace the pre-edit detail handle at the confirmed-delete boundary."""
from pathlib import Path
import hashlib
import json
import unittest
from journal_delete_current_query_delta import restore
from journal_delete_zero_nodes_delta import restore as restore_zero_nodes

ROOT = Path(__file__).resolve().parents[2]


class CurrentDeleteQueryTests(unittest.TestCase):
    def test_exact_inverse_keeps_all_other_test_bytes(self):
        c = json.loads((ROOT / 'scripts/tests/journal_delete_current_query_inverse.json').read_text())
        source = restore_zero_nodes(c['path'], (ROOT / c['path']).read_text())
        self.assertEqual(source.count(c['new']), 1)
        restored = source.replace(c['new'], c['old'], 1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), c['parent_sha256'])
        helper = source.split('private func waitUntilGone', 1)[1].split('private func uniqueDeleteAlertAction', 1)[0]
        self.assertIn('NSPredicate(format: "exists == false")', helper)
        self.assertIn('XCTWaiter.wait(for: [gone], timeout: 10)', helper)
        self.assertIn('.completed', helper)
        for forbidden in ['screenshot', 'try?', 'while ', 'sleep(', 'waitForExistence']:
            self.assertNotIn(forbidden, helper)

    def test_inverse_rejects_deleted_duplicated_and_unrelated_mutants(self):
        c = json.loads((ROOT / 'scripts/tests/journal_delete_current_query_inverse.json').read_text())
        source = restore_zero_nodes(c['path'], (ROOT / c['path']).read_text())
        self.assertEqual(hashlib.sha256(restore(c['path'], source).encode()).hexdigest(), c['parent_sha256'])
        for mutant in [source.replace(c['new'], '', 1), source + c['new'], source + '// unrelated']:
            with self.assertRaises(AssertionError):
                restore(c['path'], mutant)
