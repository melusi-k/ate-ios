from source_refusal_wording_delta import restore as pre_wording
from source_review_state_delta import restore as pre_review_state
from recipe_content_admission_delta import restore as pre_content_admission
from suggest_review_buttons_delta import restore as pre_buttons
"""Descendant source wiring and exact inverse checks. Not native qualification."""
from pathlib import Path
import hashlib,json,re,unittest
from recipe_streaming_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class RecipeStreamingPreflight(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        for path,c in json.loads((ROOT/'scripts/tests/recipe_streaming_inverse.json').read_text()).items():
            s=pre_wording(path,pre_review_state(path,pre_content_admission(path,(ROOT/path).read_text())))
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            # Fragments are live at their own chain stage: the #646 button restyle sits
            # above this layer, so fragment mutants are built after it is stripped.
            stage=pre_buttons(path,s)
            for f in c['fragments']:
                for changed in [stage.replace(f['new'],'',1),stage+f['new'],stage+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,changed)
    def test_per_request_first_pass_streams_have_no_global_sink_or_second_pass(self):
        s=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for name,end in [('extractSourceLines','func rerunRecipe'),('generateSuggestion','private func parseRecipeResult')]:
            section=s.split('static func '+name,1)[1].split(end,1)[0]
            self.assertEqual(section.count('session.streamResponse('),1)
            self.assertEqual(section.count('stream.collect()'),1)
            self.assertIn('onPreview?(',section)
            self.assertIn('try GenerationCancellation.check()',section)
            self.assertNotIn('session.respond(',section)
        self.assertNotIn('partialSink',s)
        self.assertNotIn('GenerationCancellation.optionalRepair',s)
        self.assertIn('!Self.isExampleEcho(card, sourceText: generation.prompt)',s)
        gate=s.split('static func validateImportedContent',1)[1].split('/// Only',1)[0]
        self.assertIn('ingredient || action',gate)
        self.assertIn('!RecipeQuality.isNonFoodTitle(card)',gate)
    def test_preview_is_read_only_and_tokens_accounts_deadlines_gate_publication(self):
        add=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        card=add.split('struct StreamPreviewCard:',1)[1].split('extension View',1)[0]
        self.assertIn('Partial preview, not checked or saved',card)
        for bad in ['Button(', 'saveDraft(', 'store.add(', 'RecipeEditor']:self.assertNotIn(bad,card)
        self.assertIn('generationAttempt.publish(token) { live = preview }',add)
        self.assertIn('guard loading, store.insightLifecycleAccountID == owner',add)
        self.assertIn('live = nil',add)
        self.assertEqual(add.count('60_000_000_000'),1)
        explore=(ROOT/'Ate/Logic/RecipeDiscovery.swift').read_text()
        self.assertIn('guard loading, let current = try? context()',explore)
        self.assertIn('attempt.publish(token) { preview = partial }',explore)
        self.assertIn('attempt.invalidate(); loading = false; preview = nil',explore)
        self.assertIn('guard !loading else { return false }',explore)
    def test_explicit_rerun_uses_current_card_and_keeps_original_on_error(self):
        add=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('Button { rerunCurrentDraft() }',add)
        self.assertIn('let original = draft',add)
        self.assertIn('backend.rerunRecipe(original, onPreview:',add)
        self.assertIn('Rerun took too long. Your original card is kept.',add)
        self.assertIn('draft = result; live = nil',add)
        explore=(ROOT/'Ate/Views/SuggestedNewRecipesView.swift').read_text()
        self.assertIn('Button("Rerun") { rerun(review ?? card) }',explore)
        self.assertIn('backend.rerunRecipe(card, onPreview: preview)',explore)
        session=(ROOT/'Ate/Logic/RecipeDiscovery.swift').read_text()
        self.assertIn('suggestions[index] = card',session)
        self.assertIn('suggestions.filter { $0.id != original?.id }',session)
    def test_native_proof_cases_and_snapshot_evidence_are_required_not_claimed_run(self):
        native=(ROOT/'AteTests/RecipeStreamingTests.swift').read_text()
        manifest=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        names=re.findall(r'    func (test\w+)\(',native)
        self.assertEqual(len(names),7)
        for n in names:self.assertIn('RecipeStreamingTests/'+n,manifest)
        for token in ['ImageRenderer(content: StreamPreviewCard','XCTAssertTrue(session.suggestions.isEmpty)',
                      'sink?(.init(title: "Stale partial"))','XCTAssertEqual(drafts.pending?.text, invalid)',
                      'XCTAssertEqual(calls, 1)','XCTAssertEqual(session.suggestions, [original])']:
            self.assertIn(token,native)
