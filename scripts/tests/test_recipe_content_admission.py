"""Current shared food-content wiring and exact historical preservation."""
from pathlib import Path
import hashlib,json,re,unittest
from recipe_content_admission_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class RecipeContentAdmissionPreflight(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        for path,c in json.loads((ROOT/'scripts/tests/recipe_content_admission_inverse.json').read_text()).items():
            s=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for changed in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,changed)
    def test_generation_save_and_rerun_share_actual_content_gate(self):
        backend=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        gate=backend.split('static func validateImportedContent',1)[1].split('/// Only',1)[0]
        for token in ['ingredient || action','!RecipeQuality.isNonFoodTitle(card)','card.title != "Untitled recipe"']:
            self.assertIn(token,gate)
        rerun=backend.split('func rerunRecipe',1)[1].split('static var isModelAvailable',1)[0]
        self.assertIn('try Self.validateImportedContent(result)',rerun)
        self.assertNotIn('!result.ingredients.isEmpty',rerun)
        session=(ROOT/'Ate/Logic/RecipeDiscovery.swift').read_text()
        self.assertEqual(session.count('OnDeviceBackend.validateImportedContent(card)'),2)
        self.assertNotIn('card.ingredients.filter',session)
        self.assertIn('RecipeDiscovery.excludes(card, context: current',session)
    def test_steps_only_acceptance_and_neither_content_native_cases_required(self):
        source=(ROOT/'AteTests/RecipeContentAdmissionTests.swift').read_text()
        manifest=(ROOT/'scripts/full-unit-required.txt').read_text().splitlines()
        names=re.findall(r'    func (test\w+)\(',source)
        self.assertEqual(len(names),3)
        for n in names:self.assertIn('RecipeContentAdmissionTests/'+n,manifest)
        for token in ['XCTAssertTrue(card.ingredients.isEmpty)','XCTAssertTrue(card.isEditableDraft)',
                      'XCTAssertTrue(session.save(card','XCTAssertFalse(session.save(edited',
                      'XCTAssertThrowsError(try OnDeviceBackend.validateImportedContent(invalid))',
                      'try await backend.rerunRecipe(current)','invalid.steps = []']:
            self.assertIn(token,source)
