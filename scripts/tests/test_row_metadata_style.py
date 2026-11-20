"""Source guards only. Native rendered pixels remain required."""
from pathlib import Path
import hashlib,json,unittest
from row_metadata_style_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class RowMetadataStyleTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_unrelated_changes(self):
  c=json.loads((ROOT/'scripts/tests/row_metadata_style_inverse.json').read_text());s=(ROOT/c['path']).read_text()
  self.assertEqual(hashlib.sha256(restore(c['path'],s).encode()).hexdigest(),c['parent_sha'])
  for changed in [s.replace(c['new'],'',1),s+c['new'],s+'// unrelated\n']:
   with self.assertRaises(AssertionError):restore(c['path'],changed)
 def test_native_inherited_style_and_saved_draft_screenshots_required(self):
  s=(ROOT/'AteTests/UnspecifiedServingsRowTests.swift').read_text()
  for token in ['item.labelStyle(.iconOnly)','XCTAssertEqual(actual.width, expected.width','XCTAssertGreaterThan(actual.width','servings: 0','ImageRenderer','XCTAttachment(image:','XCTAssertEqual(recipe.servings, 0)']:
   self.assertIn(token,s)
  ledger=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
  for name in ['testMetadataKeepsTextDespiteInheritedIconOnlyStyle','testSavedSourceDraftRowWithUnspecifiedServingsRetainsNativePixels']:
   self.assertEqual(ledger.count('UnspecifiedServingsRowTests/'+name),1)
