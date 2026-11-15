"""Merged-source contracts only; device golden and native execution remain required."""
from pathlib import Path
import hashlib,json,unittest
from unittest.mock import patch
from approved_merge_538 import normalize
ROOT=Path(__file__).resolve().parents[2]
HASHES={'Ate/Services/RecipeGenerationTool.swift': 'a28cb860b52a681a9872c733b20ab6eae335c96dda4b0f8f4d7f4ef240366003', 'Ate/Logic/RecipeStructureValidation.swift': 'a0a03d17eb4fd65ff7c60900b8957610b037c429d4c0cbb1a55d9361db4302ea', 'Ate/Logic/IngredientFieldNormalization.swift': '2b5eccf6908fb43b7bff1659a5c80649287a327aa82751b503d03d69edc47b4e', 'AteTests/RecipeGenerationToolTests.swift': '383e83a5743728b2e76319fa43ddf435a114a8dbf8bbbb17da4010c97c4de10d', 'docs/ai-eval.md': 'a8e578550c0f4eb3abdd468775fa9ee65e04f07610d7b965fb3368b630dc8d53', 'Ate/Resources/ProductUpdates/catalog.json': '2f57e6357081e69d177d894fa2b384d8d0dda9aedac9397b4729c174ea19d742', 'project.yml': 'da92061f0f62b72fbc1ce3edaa2cd36976c54e8bc7cc0a23788da979b50d806e', 'AteTests/AchariIngredientIdentityTests.swift': '36e3d7b0eaba967fc4b7aa28090bf00c7672d4dbf8f6d16000b76277e72e6b92', 'AteTests/GeneratedIngredientDuplicateTests.swift': 'd168d520641fec74aca23c48ace3a57fd1e2cdfaedf6586ec3170c76d95e5445', 'AteTests/JournalHomeLayoutTests.swift': 'b1cee9961e4e90c139858c8250981703aa2ea190e7bcdc5dc99965f5c53ba185', 'AteTests/PantryDraftGapTests.swift': '108a62a1621cd6ef4c605be10b20e76a6b8f629c291eca2d42f4ae0650231602', 'AteTests/ProductReleaseNotesQAFixtureTests.swift': '03fe32d77ef8451a6b758a029a269e0160a19c5c7ef69811722c1c5e062261b1', 'AteTests/ProductRoadmapTests.swift': 'efebc468dac2deb69d4cbbbddbab09db238a93144e123b32c55191d2a902a207', 'AteTests/ProductUpdatesTests.swift': '8cfedcb7d6e6292378ad5b4af94150a278f6eacc02d2c3e7bad0df440728ba76', 'AteTests/QualityAndDedupeTests.swift': '3b4fbab4c294a5c729ca11354e20363e9a6340d699956f9a8d436df4f461c0cb', 'AteTests/RepairFeedbackTests.swift': 'f936bf098ce848d3705526a5efd2b925256252031c99caa591d3803754271e92', 'AteTests/SourcePreparationBoundaryTests.swift': 'b245786558b50be89063da9ba6781758188fda386321ef49f1ac986d3cdc04b6', 'AteUITests/CookReflectionUITests.swift': '3f373b6ba7e337e0b4c38c351a3ba297d4dd6f951e7ded627aa80b002b18d1ce', 'AteUITests/DraftQualityRepairUITests.swift': 'c638406b897c3f712f133a7eff5ceac871c0d42a104b0869cd216aa31a6591c4', 'AteUITests/InsightsAcceptanceUITests.swift': 'eed8546c41d83ceed7ee1d1af50afcb7c81fcb9605aa10cdf78b55273b9c12c4', 'AteUITests/InsightsPresentationUITests.swift': 'c68c83bf89aaeed9276a569260d51f94163518ebb941c14d616f447234a52570'}
METHODS={'test28_GroupSortAndMenus': '35eaf3673231e78c562868bdab22ee5253de6f199cc1d360e26226f15c2bbd81', 'test29_ReorderMyOrder': 'd3f8921397fd80ea0ec28f83f4e0a377cd3883b782ee75481af7a2c0f2b18060', 'test29a_ReorderMyOrderSelection': '1a7483c1d1d9b5e02a80689773461f0875bb46ae9f007154aeb4f88d6e52a779', 'test29b_ReorderMyOrderActions': 'a7b888247433c089cc1dfe6c52401977edabd90a5d5bbc15238aebd3191a0c2f'}
class Merge538Contracts(unittest.TestCase):
    def test_original_generation_inputs_validation_tests_and_device_gate_exact(self):
        for file,digest in HASHES.items():self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),digest,file)
        s=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        prefix=s.split('    /// Shared by real image generation, demo fallback',1)[0].replace('#if DEBUG\nimport Darwin\n#endif\n','',1)
        self.assertEqual(hashlib.sha256(prefix.encode()).hexdigest(),'23036b8da41ae1eb10453c25e2cc58c5d47b0f9e6ec816fae873c9d19455d0be')
    def test_single_prepare_and_exclusive_four_flag_fixture(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text()
        names=['DogfoodSavedRecipeQAFixtures.prepare(st)','ExploreRetentionQAFixtures.prepare(st)','CookJournalQARoute.prepare(st)']
        for n in names:self.assertEqual(s.count(n),1)
        self.assertEqual([s.index(n) for n in names],sorted(s.index(n) for n in names))
        f=(ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertIn('guard AppConfig.isUITesting else { return }',f)
        self.assertIn('[menus, reorder, reorderAction, cook].filter { $0 }.count == 1',f)
        self.assertIn('if reorderAction { store.layout.sort = .myOrder }',f)
        self.assertIn('if cook {',f)
        self.assertIn('qa-cook-mode-saved',f)
    def test_native_bodies_preserved_and_all_selected(self):
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        for name,digest in METHODS.items():
            self.assertEqual(s.count('    func '+name+'() {'),1)
            body=s.split('    func '+name+'() {',1)[1].split('\n    }',1)[0]
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),digest,name)
            for file in ['dogfood-qualification.yml','menu-qualification.yml']:
                self.assertIn('-only-testing:AteUITests/AteUITests/'+name+' ',(ROOT/'.github/workflows'/file).read_text())
        self.assertIn("AteUITests test29a_ReorderMyOrderSelection]' passed",(ROOT/'.github/workflows/dogfood-qualification.yml').read_text())
    def test_prepare_duplicate_and_missing_mutants_fail(self):
        read=Path.read_text;target=ROOT/'Ate/App/AteApp.swift';raw=read(target);name='DogfoodSavedRecipeQAFixtures.prepare(st)'
        for changed in [raw.replace(name,''),raw.replace(name,name+'; '+name)]:
            with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==target else read(p,*a,**k)):
                with self.assertRaises(AssertionError):self.test_single_prepare_and_exclusive_four_flag_fixture()
    def test_inverse_exact_count_mutants_fail(self):
        data=json.loads((ROOT/'scripts/tests/approved_merge_538_inverses.json').read_text())
        for key,c in data['contracts'].items():
            raw=(ROOT/c['path']).read_text()
            for item in c['inverse_fragments']:
                old=item['merged_fragment']
                for changed in [raw.replace(old,'',1),raw+old]:
                    with self.assertRaises(AssertionError):normalize(key,changed)
    def test_original_assertion_input_selection_ocr_and_budget_mutants_fail_original_guards(self):
        import importlib
        cases=[('test_add_title_query_diagnostic','AddTitleQueryDiagnosticTests','test_all_original_tests_and_helpers_preserved','AteUITests/AteUITests.swift','XCTAssertTrue(','XCTAssertFalse('),
          ('test_add_title_query_diagnostic','AddTitleQueryDiagnosticTests','test_all_original_tests_and_helpers_preserved','AteUITests/AteUITests.swift','.tap()','.doubleTap()'),
          ('test_ocr_cpu_capture','OCRCPUCaptureContracts','test_only_observation_changes','Ate/Services/OnDeviceBackend.swift','req.recognitionLevel = .accurate','req.recognitionLevel = .fast'),
          ('test_search_receipt_diagnostic','SearchReceiptTests','test_exact_original_library_and_workflow_reconstruct','.github/workflows/compile-check.yml','-only-testing:AteTests','-only-testing:MissingTests'),
          ('test_search_receipt_diagnostic','SearchReceiptTests','test_exact_original_library_and_workflow_reconstruct','.github/workflows/compile-check.yml','-default-test-execution-time-allowance 240','-default-test-execution-time-allowance 999')]
        read=Path.read_text
        for mod,cls,method,file,old,new in cases:
            target=ROOT/file;raw=read(target);self.assertIn(old,raw);changed=raw.replace(old,new,1)
            with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==target else read(p,*a,**k)):
                with self.assertRaises(AssertionError):getattr(getattr(importlib.import_module(mod),cls)(),method)()
