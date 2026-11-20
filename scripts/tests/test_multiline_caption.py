"""Static source/route checks only; never native Swift/device qualification."""
from pathlib import Path
import hashlib,json,re,unittest
from multiline_caption_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class MultilineCaptionTests(unittest.TestCase):
 def test_exact_backend_inverse_and_all_missing_duplicate_unrelated_mutants(self):
  for path,c in json.loads((ROOT/'scripts/tests/multiline_caption_inverse.json').read_text()).items():
   s=(ROOT/path).read_text()
   self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
   for mutant in [s.replace(c['new'],'',1),s+c['new'],s+'// unrelated\n']:
    # Removing the whole additive route is exactly the historical parent;
    # duplicated/modified routes and unrelated changes must fail closed.
    if mutant==restore(path,s):continue
    with self.assertRaises(AssertionError):restore(path,mutant)
   with self.assertRaises(AssertionError):restore(path,s.replace('MultilineCaptionImport.card(text)','MultilineCaptionImport.card(text + "changed")',1))
 def test_deterministic_route_precedes_model_and_preserves_source_rows(self):
  s=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text().split('private func importSource(',1)[1].split('@MainActor',1)[0]
  self.assertLess(s.index('MultilineCaptionImport.card(text)'),s.index('if modelAvailable()'))
  p=(ROOT/'Ate/Logic/MultilineCaptionImport.swift').read_text()
  for token in ['items.map { .init(name: $0, quantity: 0, unit: "", notes: nil) }','instruction: $0.element, timeSeconds: nil','sourceDraft = .init(text: text','servings: exactServings ?? 0','unknownServings: exactServings == nil','markers.count == 1']:
   self.assertIn(token,p)
  for token in ['IngredientParser','LanguageModelSession','selectSourceLines','timeMinutes:', 'split(separator: ".")','Task.sleep']:
   self.assertNotIn(token,p)
 def test_exact_native_cases_cover_two_and_three_row_classifiers_both_pastes(self):
  p=(ROOT/'AteTests/MultilineCaptionImportTests.swift').read_text()
  for token in ['Sample caption, paste as is:','Garlic butter chicken thighs 🍗','3 cloves garlic, minced','salt and pepper','for count in [2, 3]','for available in [true, false]','(caption, 1, 2), (unframed, 0, 1)','XCTAssertEqual(classifierCalls, 0)','JSONDecoder().decode','XCTAssertNil(card.timeMinutes']:
   self.assertIn(token,p)
  ledger=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
  for name in re.findall(r'func (test\w+)\(',p):self.assertEqual(ledger.count('MultilineCaptionImportTests/'+name),1)
