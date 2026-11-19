"""Add no-source boundary supplements native tests, not device qualification."""
from pathlib import Path
import unittest,json,hashlib,re
from add_prompt_source_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class AddPromptSourceTests(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        fixture=json.loads((ROOT/'scripts/tests/add_prompt_source_inverse.json').read_text())
        for path,c in fixture.items():
            text=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,text).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for mutant in [text.replace(f['new'],'',1),text+f['new'],text+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,mutant)
    def test_actual_add_routes_every_primary_through_pre_backend_source_gate(self):
        view=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        gate=view.split('enum AddPromptSourceImport {',1)[1].split('struct AddRecipeSheet:',1)[0]
        self.assertIn('request.mode == .prompt, case .none = SourceRecipeFidelity.extraction',gate)
        self.assertLess(gate.index('throw BackendError'),gate.index('backend.parseRecipeWithContract'))
        self.assertIn('try GenerationCancellation.check()',gate)
        self.assertIn('let parsed = try await AddPromptSourceImport.parse(req, using: store.backend)',view)
        self.assertNotIn('let parsed = try await store.backend.parseRecipeWithContract(req)',view)
        self.assertIn('DraftStore.shared.begin(mode: mode.rawValue',view)
        self.assertIn('} else if let q = dishQuestion, error == nil {',view)
        self.assertIn('Paste the full recipe, including ingredients and method.',view)
        self.assertNotIn('Generate a new recipe from your idea',view)
    def test_all_real_boundary_cases_required_and_explore_kept_separate(self):
        source=(ROOT/'AteTests/AddPromptSourceImportTests.swift').read_text()
        required=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        for name in re.findall(r'    func (test\w+)\(',source):self.assertIn('AddPromptSourceImportTests/'+name,required)
        self.assertIn('Eggs Benedict',source)
        self.assertIn('XCTAssertTrue(backend.requests.isEmpty',source)
        self.assertIn('SourceRecipeFidelity.extraction(source)',source)
        self.assertIn('OnDeviceBackend(fallback:',source)
        backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertIn('func suggestRecipe(_ generation: RecipeDiscoveryGeneration)',backend)
        self.assertEqual(backend.count('discovery: true'),1)
        self.assertNotIn('partialSink',backend)
