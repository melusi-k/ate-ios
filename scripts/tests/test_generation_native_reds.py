"""Source guards only, never native Swift qualification."""
from pathlib import Path
import hashlib,json,re,unittest
from multiline_caption_delta import restore as pre_multiline
from generation_native_reds_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class GenerationNativeRedTests(unittest.TestCase):
 def test_exact_inverse_rejects_missing_duplicate_and_unrelated_edits(self):
  for path,c in json.loads((ROOT/'scripts/tests/generation_native_reds_inverse.json').read_text()).items():
   s=pre_multiline(path,(ROOT/path).read_text());self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
   for f in c['fragments']:
    for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
     with self.assertRaises(AssertionError):restore(path,changed)
 def test_preview_notnil_precedes_suspension_and_expiry_is_observed(self):
  s=(ROOT/'AteTests/RecipeStreamingTests.swift').read_text().split('func testCancellationDeadlineAccountChangeAndNewRequestIsolateRetainedSinks()',1)[1].split('func testRerun',1)[0]
  self.assertLess(s.index('XCTAssertNotNil(session.preview'),s.index('started.fulfill()'))
  self.assertEqual(s.count('XCTAssertNotNil(session.preview'),1)
  self.assertIn('20_000_000 : 60_000_000_000',s)
  self.assertNotIn('Task.sleep',s)
  self.assertIn('await fulfillment(of: [expired], timeout: 2)',s)
  for x in ['observer.cancel()', 'session.message?.contains("took too long")', 'sink?(.init(title: "Stale partial"))', 'sink?(.init(title: "Old sink must not overwrite"))', 'XCTAssertEqual(session.suggestions.map(\\.title), ["New result"])','XCTAssertTrue(session.savedIDs.isEmpty)']:
   self.assertIn(x,s)
 def test_inline_converter_is_narrow_before_model_and_unknowns_stay_unknown(self):
  s=(ROOT/'Ate/Logic/SourceDraftImport.swift').read_text().split('static func inlineCaptionCard(',1)[1].split('static func card(',1)[0]
  for x in ['SourceRecipeFidelity.inlineCaption(text)', 'ingredients: contract.ingredients','instruction: contract.method, timeSeconds: nil','servings: exactServings ?? 0','source: .imported','sourceDraft = .init(text: text','unknownServings: exactServings == nil','contract.issues(card).isEmpty']:
   self.assertIn(x,s)
  for x in ['pastedSource =','timeMinutes:', 'split(separator:', 'modelAvailable','selectSourceLines']:self.assertNotIn(x,s)
  route=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text().split('private func importSource(',1)[1].split('@MainActor',1)[0]
  self.assertLess(route.index('SourceDraftImport.inlineCaptionCard(text)'),route.index('if modelAvailable()'))
  self.assertEqual(route.count('selectSourceLines(text, onPreview)'),1)
 def test_original_caption_assertion_strengthened_and_native_cases_required(self):
  s=(ROOT/'AteTests/SourceRecipeFidelityTests.swift').read_text();method=s.split('func testF1UnavailableModelDoesNotSubstituteDemoForExplicitSource()',1)[1].split('func testVerifiedInline',1)[0]
  for x in ['XCTAssertFalse(card.ingredients.isEmpty)','[2, 2, 3, 1, 2]','["pcs", "pcs", "pcs", "tin", "tsp"]','XCTAssertEqual(card.servings, 0)','XCTAssertNil(card.pastedSource)']:self.assertIn(x,method)
  names=['testF1UnavailableModelDoesNotSubstituteDemoForExplicitSource','testVerifiedInlineCaptionKeepsExactKnownFactsWithoutCallingFailingClassifier','testAmbiguousInlineCaptionCannotGainInventedDeterministicIngredients']
  ledger=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
  for name in names:self.assertEqual(ledger.count('SourceRecipeFidelityTests/'+name),1)
  self.assertIn('XCTAssertEqual(modelCalls, 0); XCTAssertEqual(classifierCalls, 0); XCTAssertEqual(fallback.parses, 0)',s)
