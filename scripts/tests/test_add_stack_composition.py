from verified_paste_import_delta import restore as pre_simplification
"""Sibling composition is exact, additive and preserves both original inverses."""
from pathlib import Path
import unittest,json,hashlib
from add_stack_composition_delta import parent_source
from add_generation_deadline_delta import restore as deadline
ROOT=Path(__file__).resolve().parents[2]
class AddStackCompositionTests(unittest.TestCase):
    def test_exact_parent_restoration_rejects_missing_duplicate_and_unrelated_changes(self):
        path='Ate/Services/OnDeviceBackend.swift'
        source=deadline(path,(ROOT/path).read_text())
        contracts=json.loads((ROOT/'scripts/tests/add_stack_composition_inverse.json').read_text())
        for label,c in contracts.items():
            self.assertEqual(hashlib.sha256(parent_source(label,path,source).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for changed in [source.replace(f['new'],'',1),source+f['new'],source+'// unrelated change\n']:
                    with self.assertRaises(AssertionError):parent_source(label,path,changed)
    def test_parent_fixtures_are_unchanged_and_live_stream_remains_private(self):
        pins={'prompt_draft_boundary_inverse.json':'05aebc07ba400c66e6d78f3537bad0faf1d0226df2d731bf91d40c8d17e432ca','recipe_discovery_intent_inverse.json':'d7010c178b0e83d636776bd66b5ef96002a21283c0e8161801a59a927d2a1744'}
        for p,h in pins.items():self.assertEqual(hashlib.sha256((ROOT/'scripts/tests'/p).read_bytes()).hexdigest(),h)
        backend=pre_simplification('Ate/Services/OnDeviceBackend.swift',(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text())
        view=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertNotIn('partialSink',backend+view)
        self.assertNotIn('emitPreview',backend)
        self.assertIn('discovery: Bool = false',backend)
        self.assertEqual(backend.count('discovery: true'),1)
        self.assertIn('RecipeIdeaPrompt.build(text, confirmedDish: request.dishHint)',backend)
