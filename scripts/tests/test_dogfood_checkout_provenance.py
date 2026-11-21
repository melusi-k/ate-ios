"""Checkout provenance is event-owned, receipts still fail closed on pinned mismatch."""
from pathlib import Path
import hashlib,json,unittest,yaml
from dogfood_checkout_provenance_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class DogfoodCheckoutProvenanceTests(unittest.TestCase):
    def test_exact_four_ref_delta_and_missing_duplicate_unrelated_mutants(self):
        c=json.loads((ROOT/'scripts/tests/dogfood_checkout_provenance_inverse.json').read_text())
        source=(ROOT/c['path']).read_text();old=restore(c['path'],source)
        self.assertEqual(hashlib.sha256(old.encode()).hexdigest(),c['parent_sha'])
        self.assertEqual(source.replace(c['new'],c['old']),old)
        self.assertEqual(source.count(c['new']),4)
        for mutant in [source.replace(c['new'],c['old'],1),source+c['new'],source+'# unrelated\n']:
            with self.assertRaises(AssertionError):restore(c['path'],mutant)
    def test_event_checkout_precedes_frozen_equality_and_no_gate_or_cache_change(self):
        c=json.loads((ROOT/'scripts/tests/dogfood_checkout_provenance_inverse.json').read_text())
        source=(ROOT/c['path']).read_text();old=restore(c['path'],source)
        before=yaml.safe_load(old)['jobs'];after=yaml.safe_load(source)['jobs']
        event='${{ github.event.pull_request.head.sha || github.sha }}'
        self.assertEqual(before['pin-source'],after['pin-source'])
        self.assertEqual(before['dogfood-qualification']['steps'][1:],after['dogfood-qualification']['steps'][1:])
        for lane in ['qa-critical-flows','library-popup','sync-quarantine']:
            steps=after[lane]['steps']
            self.assertEqual(steps[0]['with']['ref'],event)
            self.assertEqual(steps[1]['env']['EXPECTED_SOURCE'],'${{ needs.pin-source.outputs.sha }}')
            self.assertIn('ci-lane-receipt.py verify --expected',steps[1]['run'])
            self.assertEqual(before[lane]['steps'][1:],steps[1:])
        self.assertNotIn('ref: ${{ needs.pin-source.outputs.sha }}',source)
        self.assertEqual(after['pin-source']['steps'][0]['env']['EVENT_SOURCE'],event)
        # PR uses immutable event head; dispatch has no PR object and uses immutable run SHA.
        for pr,run in [('a'*40,'b'*40),('', 'c'*40)]:
            pinned=pr or run;checkout=pr or run
            self.assertEqual(checkout,pinned)
        helper=(ROOT/'scripts/ci-lane-receipt.py').read_text()
        self.assertIn('HEAD',helper)
        self.assertIn('expected',helper)
