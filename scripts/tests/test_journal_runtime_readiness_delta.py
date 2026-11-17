import unittest
from pathlib import Path
from journal_runtime_readiness_delta import restore, FRAGMENTS
ROOT=Path(__file__).resolve().parents[2]
class JournalRuntimeReadinessContracts(unittest.TestCase):
    def test_whole_workflow_pin_rejects_unreviewed_mutations(self):
        source=(ROOT/'.github/workflows/journal-open-state-ui.yml').read_text()
        for addition in ['      - name: Mirror retained Journal screenshots after XCTest\n        if: always()\n        run: |\n          python3 scripts/mirror-journal-snapshots.py --raw-directory ui-screenshots/raw --output journal-snapshot-mirror.log\n','            journal-snapshot-mirror.log\n']:
            self.assertEqual(source.count(addition),1)
            source=source.replace(addition,'',1)
        restored=restore(source)
        self.assertEqual(restore(restored),restored)
        for changed in [source+'# mutation\n', source.replace('bootstatus', 'altered-bootstatus',1)]:
            with self.assertRaises(AssertionError): restore(changed)
        if FRAGMENTS[0][0] in source:
            for new,_ in FRAGMENTS:
                for changed in [source.replace(new,'',1),source+new]:
                    with self.assertRaises(AssertionError):restore(changed)
