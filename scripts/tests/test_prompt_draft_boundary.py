"""Prompt boundary source checks supplement native tests; not model qualification."""
from pathlib import Path
import hashlib,json,re,unittest
from prompt_draft_boundary_delta import restore
ROOT=Path(__file__).resolve().parents[2]

class PromptDraftBoundarySourceTests(unittest.TestCase):
    def test_inverse_reconstructs_parent_and_refuses_missing_duplicate_or_changed_source(self):
        fixture=json.loads((ROOT/'scripts/tests/prompt_draft_boundary_inverse.json').read_text())
        for path, contract in fixture.items():
            source=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,source).encode()).hexdigest(),contract['parent_sha'])
            for f in contract['fragments']:
                for mutant in [source.replace(f['new'],'',1),source+f['new'],source+'// unrelated change\n']:
                    with self.assertRaises(AssertionError):restore(path,mutant)

    def test_no_unaccepted_snapshot_channel_and_cancellation_still_drains_stream(self):
        backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        view=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertNotIn('partialSink',backend+view)
        self.assertNotIn('StreamPreviewCard(preview:',view)
        self.assertNotIn('emitPreview',backend)
        self.assertIn('for try await _ in stream {\n                    try GenerationCancellation.check()\n                }',backend)
        self.assertIn('let res = try await stream.collect()',backend)
        self.assertIn('Checking the recipe before review.',view)
        self.assertIn('guard generationAttempt.isCurrent(token) else { return }',view)
        self.assertLess(view.index('let parsed = try await store.backend.parseRecipeWithContract(req)'),view.index('draft = normalized',view.index('let parsed = try await store.backend.parseRecipeWithContract(req)')))
        self.assertIn('return RecipeDraftRepair.automaticImproves',backend)
        self.assertIn('if Self.isExampleEcho(card, sourceText:',backend)
        self.assertIn('sampling: .greedy',backend)

    def test_confirmation_only_conditions_unbound_generation_and_never_renames_output(self):
        backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        fragment=backend.split('case .prompt:',1)[1].split('case .url where',1)[0]
        self.assertIn('if let fidelity {',fragment)
        self.assertIn('prompt = RecipePrompt.social(caption: fidelity.text)',fragment)
        self.assertIn('} else {\n                prompt = RecipeIdeaPrompt.build(text, confirmedDish: request.dishHint)',fragment)
        self.assertIn('contextUser = text + "\\n" + (request.dishHint ?? "")',fragment)
        helper=(ROOT/'Ate/Logic/RecipeIdeaPrompt.swift').read_text()
        self.assertNotIn('.title =',helper)
        self.assertNotIn('aiConfidence',helper)
        self.assertIn('RecipePrompt.prompt(text)',helper)
        self.assertIn('explain the uncertainty',helper)

    def test_native_regressions_required_and_oven_check_remains_step_local(self):
        source=(ROOT/'AteTests/PromptDraftBoundaryTests.swift').read_text()
        required=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        for name in re.findall(r'    func (test\w+)\(',source):self.assertIn('PromptDraftBoundaryTests/'+name,required)
        quality=(ROOT/'Ate/Logic/RecipeQuality.swift').read_text()
        self.assertIn('requiresOvenTemperature(s.instruction) && !hasTemperature(s.instruction)',quality)
        self.assertIn('return ovenWords.contains { heating.lowercased().contains($0) }',quality)
        self.assertIn('!issues(c).isEmpty',quality)
