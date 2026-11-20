from source_refusal_route_delta import restore as pre_route
"""Exact wording-only guard; native behavior must still be run."""
from pathlib import Path
import hashlib,json,unittest
from source_refusal_wording_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class SourceRefusalWordingTests(unittest.TestCase):
 def test_one_line_only_inverse_refuses_missing_duplicate_or_unrelated_changes(self):
  c=json.loads((ROOT/'scripts/tests/source_refusal_wording_inverse.json').read_text());s=pre_route(c['path'],(ROOT/c['path']).read_text())
  self.assertEqual(hashlib.sha256(restore(c['path'],s).encode()).hexdigest(),c['parent_sha'])
  self.assertEqual(c['new'].count('\n'),1)
  self.assertIn('static let missingSourceMessage =',c['new'])
  for changed in [s.replace(c['new'],'',1),s+c['new'],s+'// unrelated\n']:
   with self.assertRaises(AssertionError):restore(c['path'],changed)
 def test_native_both_refusals_keep_no_generation_and_relevant_copy(self):
  s=(ROOT/'AteTests/SourceRefusalWordingTests.swift').read_text()
  for token in ['Beef stroganoff','The quarterly report is due Friday.','Nothing was generated.','XCTAssertFalse(SourceDraftImport.hasSource(text))','XCTAssertEqual(availabilityChecks, 0)','XCTAssertEqual(modelCalls, 0)','XCTAssertEqual(error.localizedDescription, expected)']:
   self.assertIn(token,s)
  self.assertIn('SourceRefusalWordingTests/testBareDishAndNonFoodKeepRefusalWithRelevantWordingAndNoModelCall',(ROOT/'scripts/full-unit-required.txt').read_text().splitlines())

 def test_followup_route_copy_inverse_and_no_false_explore_pointer(self):
  c=json.loads((ROOT/'scripts/tests/source_refusal_route_inverse.json').read_text());s=(ROOT/c['path']).read_text()
  self.assertEqual(hashlib.sha256(pre_route(c['path'],s).encode()).hexdigest(),c['parent_sha'])
  self.assertNotIn('Explore',c['new'])
  self.assertIn('Nothing was generated.',c['new'])
  for changed in [s.replace(c['new'],'',1),s+c['new'],s+'// unrelated\n']:
   with self.assertRaises(AssertionError):pre_route(c['path'],changed)
