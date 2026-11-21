"""Static preservation/ordering guards, not native Swift execution."""
from pathlib import Path
import hashlib,json,unittest
from streaming_echo_completion_delta import restore
ROOT=Path(__file__).resolve().parents[2]

class StreamingEchoCompletionTests(unittest.TestCase):
 def test_exact_inverse_and_missing_duplicate_unrelated_mutants(self):
  c=json.loads((ROOT/'scripts/tests/streaming_echo_completion_inverse.json').read_text())
  s=(ROOT/c['path']).read_text()
  self.assertEqual(hashlib.sha256(restore(c['path'],s).encode()).hexdigest(),c['parent_sha'])
  self.assertEqual(restore(c['path'],s.encode()),restore(c['path'],s).encode())
  for f in c['fragments']:
   for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
    with self.assertRaises(AssertionError):restore(c['path'],changed)
 def test_real_session_settlement_precedes_all_original_final_checks(self):
  s=(ROOT/'AteTests/RecipeStreamingTests.swift').read_text().split('func testRejectedExampleEchoPreviewNeverBecomesSavable()',1)[1]
  boundary=s.index('await fulfillment(of: [settled], timeout: 2)')
  for token in ['XCTAssertFalse(session.loading)','XCTAssertNil(session.preview)','XCTAssertNotNil(session.message)','XCTAssertEqual(session.message, "AI could not create a suggestion. No demo recipe was substituted or saved.")']:
   self.assertGreater(s.index(token),boundary)
  self.assertIn('while session.loading && !Task.isCancelled { await Task.yield() }',s)
  self.assertGreater(s.index('observer.cancel()'),boundary)
  self.assertIn('gate.release(); await fulfillment(of: [returned], timeout: 2)',s)
  for token in ['Task.sleep','timeoutNanoseconds:','XCTSkip','try?','continueAfterFailure']:
   self.assertNotIn(token,s)
 def test_injected_fixture_meets_existing_product_echo_guard(self):
  s=(ROOT/'AteTests/RecipeStreamingTests.swift').read_text().split('func testRejectedExampleEchoPreviewNeverBecomesSavable()',1)[1]
  self.assertIn('["beef tripe", "onions", "garlic", "curry powder", "beef stock"]',s)
  backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
  self.assertIn('!Self.isExampleEcho(card, sourceText: generation.prompt)',backend)
  self.assertIn('return hits.contains("beef tripe") && hits.count >= 4',backend)
