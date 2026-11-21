from recipe_streaming_delta import restore as pre_streaming
"""Exact import preservation plus typed creative boundary; not live model proof."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from recipe_discovery_intent_delta import restore
from add_stack_composition_delta import parent_source
from add_generation_deadline_delta import restore as restore_deadline
ROOT = Path(__file__).resolve().parents[2]

class RecipeDiscoveryIntentSourceTests(unittest.TestCase):
    def test_exact_inverse_restores_all_three_parent_sources(self):
        contracts = json.loads((ROOT / 'scripts/tests/recipe_discovery_intent_inverse.json').read_text())
        for path, contract in contracts.items():
            text = parent_source('explore',path,restore_deadline(path,(ROOT / path).read_text()))
            self.assertEqual(hashlib.sha256(restore(path, text).encode()).hexdigest(), contract['parent_sha'])
            for fragment in contract['fragments']:
                for changed in [text.replace(fragment['new'], '', 1), text + fragment['new']]:
                    with self.assertRaises(AssertionError): restore(path, changed)

    def test_only_typed_discovery_selects_private_creative_path(self):
        source = pre_streaming('Ate/Services/OnDeviceBackend.swift',(ROOT / 'Ate/Services/OnDeviceBackend.swift').read_text())
        typed = source.split('func suggestRecipe(', 1)[1].split('private func parseRecipeResult', 1)[0]
        self.assertIn('RecipeDiscoveryGeneration', typed)
        self.assertIn('createSuggestion(generation.prompt)', typed)
        self.assertEqual(source.count('createSuggestion(generation.prompt)'), 1)
        regular = source.split('func parseRecipeWithContract(', 1)[1].split('func suggestRecipe(', 1)[0]
        self.assertIn('parseRecipeResult(request)', regular)
        self.assertNotIn('discovery: true', regular)
        self.assertIn('discovery: Bool = false', source)
        self.assertIn('if !discovery, request.mode == .prompt {', source)
        request = (ROOT / 'Ate/Services/BackendService.swift').read_text().split('struct ParseRequest:', 1)[1].split('struct BackendError', 1)[0]
        self.assertNotIn('discovery', request)
        discovery = pre_streaming('Ate/Logic/RecipeDiscovery.swift',(ROOT / 'Ate/Logic/RecipeDiscovery.swift').read_text())
        self.assertIn('init(context: RecipeDiscoveryContext, suggested: [RecipeCard])', discovery)
        self.assertNotIn('init(prompt:', discovery)

    def test_retry_is_explicit_and_deadline_and_safety_checks_remain(self):
        source = pre_streaming('Ate/Logic/RecipeDiscovery.swift',(ROOT / 'Ate/Logic/RecipeDiscovery.swift').read_text())
        self.assertIn('timeoutNanoseconds: UInt64 = 60_000_000_000', source)
        self.assertIn('cancel() // revoke the publication token', source)
        for token in ['result.source == .appleIntelligence', 'RecipeQuality.isNonFoodTitle(card)', 'current.owner == input.owner', 'current.owner == owner', 'RecipeDiscovery.excludes(card, context: current']:
            self.assertIn(token, source)
        view = pre_streaming('Ate/Views/SuggestedNewRecipesView.swift',(ROOT / 'Ate/Views/SuggestedNewRecipesView.swift').read_text())
        self.assertIn('backend.suggestRecipe($0)', view)
        self.assertIn('"Try again"', view)
        self.assertIn('.disabled(session.loading)', view)
        self.assertIn('clearPendingDraft: false', view)

    def test_real_pre_model_regression_cases_are_required(self):
        source = (ROOT / 'AteTests/RecipeDiscoveryIntentTests.swift').read_text()
        required = (ROOT / 'scripts/full-unit-required.txt').read_text().splitlines()
        for name in re.findall(r'    func (test\w+)\(', source):
            self.assertIn('RecipeDiscoveryIntentTests/' + name, required)
        self.assertIn('SourceRecipeFidelity.extraction(generation.prompt)', source)
        self.assertIn('backend.suggestRecipe(generation)', source)
        self.assertIn('backend.parseRecipe(ParseRequest(mode: .prompt, text: input().prompt))', source)
        self.assertIn('XCTAssertTrue(fallback.requests.isEmpty)', source)
