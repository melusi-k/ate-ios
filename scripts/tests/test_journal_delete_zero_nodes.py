"""Pin the sole count-query candidate without weakening native absence checks."""
from pathlib import Path
import hashlib
import json
import unittest
from journal_delete_zero_nodes_delta import restore
ROOT = Path(__file__).resolve().parents[2]

class ZeroDetailNodesTests(unittest.TestCase):
    def test_exact_inverse_and_absence_contract(self):
        c = json.loads((ROOT / 'scripts/tests/journal_delete_zero_nodes_inverse.json').read_text())
        source = (ROOT / c['path']).read_text()
        self.assertEqual(hashlib.sha256(restore(c['path'], source).encode()).hexdigest(), c['parent_sha256'])
        self.assertIn('app.descendants(matching: .any).matching(identifier: "journal.detail.text")', c['new'])
        self.assertIn('detailNodes.count == 0', c['new'])
        self.assertIn('XCTWaiter.wait(for: [noDetailNodes], timeout: 10), .completed', c['new'])
        for forbidden in ['firstMatch', 'sleep(', 'try?', 'while ', 'waitForExistence']:
            self.assertNotIn(forbidden, '\n'.join(x for x in c['new'].splitlines() if not x.lstrip().startswith('//')))
        for mutant in [source.replace(c['new'], '', 1), source + c['new'], source + '// unrelated', source.replace('detailNodes.count == 0', 'detailNodes.count <= 1')]:
            with self.assertRaises(AssertionError):
                restore(c['path'], mutant)
