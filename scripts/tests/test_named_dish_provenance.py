"""#512 source/routing contracts, not model, native or pixel acceptance."""
from pathlib import Path
import hashlib, unittest
ROOT=Path(__file__).resolve().parents[2]
SCOPE='''        let reconstructedFromMenu = NamedDishProvenance.needsNotice(
            source: input == .prompt ? contextUser : (input == .social ? contextSource : ""))
'''
APPLY='        if reconstructedFromMenu { card = NamedDishProvenance.apply(card) }\n'
def restore_named_dish_provenance(test, s):
    for token in [SCOPE,APPLY]:
        test.assertEqual(s.count(token),1)
        s=s.replace(token,'',1)
    test.assertEqual(s.count('emitPreview: fidelity == nil && !reconstructedFromMenu'),2)
    return s.replace('emitPreview: fidelity == nil && !reconstructedFromMenu','emitPreview: fidelity == nil')
class NamedDishProvenanceContracts(unittest.TestCase):
    def test_exact_original_backend_reconstructs(self):
        s=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertEqual(hashlib.sha256(restore_named_dish_provenance(self,s).encode()).hexdigest(),'7483038b7d3649a9fde0e4b99bdb2ace7a8a811e71190145e34f3f14ad6dc609')
    def test_source_scoped_after_repair_before_accepted_card(self):
        s=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertLess(s.index('GenerationCancellation.optionalRepair'),s.index(APPLY))
        self.assertLess(s.index(APPLY),s.index('var normalized = RecipeLogic.normalize(card)'))
        self.assertIn('input == .prompt ? contextUser : (input == .social ? contextSource : "")',s)
    def test_notice_is_unconditional_and_source_fact_is_clear(self):
        s=(ROOT/'Ate/Logic/NamedDishProvenance.swift').read_text()
        for token in ['CaptionAnalysis.isPromo(source)', '!CaptionAnalysis.hasRecipeSignals(source)',
                      '!CuisineGlossary.matches(in: source).isEmpty','Best-effort traditional version',
                      'did not provide a source recipe','Dish-name confidence','no source recipe; ingredients and method are suggestions']:
            self.assertIn(token,s)
        for token in ['card.title =','card.ingredients =','card.steps =','card.servings =','card.source =','card.aiConfidence =']:
            self.assertNotIn(token,s)
    def test_missing_duplicate_and_preview_mutants_fail(self):
        source=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for changed in [source.replace(APPLY,''),source+SCOPE,source.replace(' && !reconstructedFromMenu','',1)]:
            with self.assertRaises(AssertionError): restore_named_dish_provenance(self,changed)
    def test_original_native_photo_and_ocr_fixtures_unchanged(self):
        for file,expected in ORIGINAL_NATIVE.items():
            self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),expected,file)


    def test_draft_confidence_uses_source_qualified_copy(self):
        s=(ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()
        self.assertIn('Label(NamedDishProvenance.confidenceLabel(conf, card: d),',s)

ORIGINAL_NATIVE = {'AteTests/OCRTerminalResultTests.swift': 'da0d9653ef2a33928536320a3da3435160fa7318eb7cfc606937178616ed8816', 'AteTests/RecipePromptTests.swift': '11d6a434eb4348a1002d81083d22388d95c1297038a663cbb904e3766d59b63d', 'AteUITests/KeyFlowsQATests.swift': 'c07bdfa3a5a831f9fac67e546a6ab6607e73f141f7f6793cd8d1d6c6bb69d629'}
