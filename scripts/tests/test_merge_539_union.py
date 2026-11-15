"""Raw merged-source invariants; Python is not native compile, XCTest or pixel proof."""
from pathlib import Path
import hashlib,json,unittest
from unittest.mock import patch
from approved_merge_539 import normalize,approved_original_file,normalize_539_parent
from journal_personal_reset_delta import restore as restore_journal_reset
ROOT=Path(__file__).resolve().parents[2]
METHODS={'test28_GroupSortAndMenus': 'e30851c026ccfa7a36ff5d828c7e0f204bf21021eba9a4e6383c715429b4bc67', 'test29_ReorderMyOrder': 'f30fa14b1a5774dc41b193c2d6bdac4be296ccc412ec38d432ea3a5a4970c5db', 'test28_GroupSortAndMenusSavedSetup': '35eaf3673231e78c562868bdab22ee5253de6f199cc1d360e26226f15c2bbd81', 'test29_ReorderMyOrderSavedSetup': '1a7483c1d1d9b5e02a80689773461f0875bb46ae9f007154aeb4f88d6e52a779', 'test29b_ReorderMyOrderActions': 'a7b888247433c089cc1dfe6c52401977edabd90a5d5bbc15238aebd3191a0c2f'}
class Merge539Union(unittest.TestCase):
    def test_original_live_and_saved_setup_native_bodies_exact(self):
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        for method,digest in METHODS.items():
            self.assertEqual(s.count('    func '+method+'() {'),1)
            body=s.split('    func '+method+'() {',1)[1].split('\n    }',1)[0]
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),digest,method)
    def test_all_native_variants_selected_without_budget_changes(self):
        for file in ['dogfood-qualification.yml','menu-qualification.yml']:
            s=(ROOT/'.github/workflows'/file).read_text()
            for method in METHODS:self.assertIn('-only-testing:AteUITests/AteUITests/'+method+' \\\n',s)
            if file=='dogfood-qualification.yml':self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',s)
        s=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        self.assertIn('for test in test28_GroupSortAndMenus test29_ReorderMyOrder test29b_ReorderMyOrderActions; do',s)
        self.assertIn('for test in test28_GroupSortAndMenusSavedSetup test29_ReorderMyOrderSavedSetup; do',s)
        self.assertIn('missing saved-setup Library pass',s)
    def test_single_prepare_count_and_order(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text()
        names=['DogfoodSavedRecipeQAFixtures.prepare(st)','ExploreRetentionQAFixtures.prepare(st)','CookJournalQARoute.prepare(st)']
        for n in names:self.assertEqual(s.count(n),1,n)
        self.assertEqual([s.index(n) for n in names],sorted(s.index(n) for n in names))
    def test_prepare_duplicate_and_missing_mutants_fail(self):
        target=ROOT/'Ate/App/AteApp.swift';read=Path.read_text;raw=read(target);call='DogfoodSavedRecipeQAFixtures.prepare(st)'
        for changed in [raw.replace(call,call+'; '+call),raw.replace(call,'')]:
            with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==target else read(p,*a,**k)):
                with self.assertRaises(AssertionError):self.test_single_prepare_count_and_order()
    def test_single_inner_cook_inset_and_outer_numeric_measurement(self):
        s=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        for token in ['Label("Cook mode", systemImage: "frying.pan")','store.beginCookSession(recipeID: recipeID, factor: factor)','.safeAreaInset(edge: .bottom, spacing: 0)']:
            self.assertEqual(s.count(token),1)
        self.assertLess(s.index('.safeAreaInset(edge: .bottom'),s.index('RecipeNotFoundView(title:'))
        self.assertLess(s.index('RecipeNotFoundView(title:'),s.index('.background(GeometryReader { geometry in'))
        self.assertIn('QA8DetailLayoutDiagnostic.event("detail-host-bottom"',s)
        self.assertIn('hostBottomY = value',s)
        self.assertIn('.padding(.bottom, footerChromeReserve)',s)
    def test_inverse_fragment_count_order_and_fixture_tamper_mutants(self):
        fixture=ROOT/'scripts/tests/approved_merge_539_inverses.json'
        data=json.loads(fixture.read_text())
        for key,contract in data['contracts'].items():
            raw=restore_journal_reset(key,(ROOT/contract['path']).read_text())
            for item in contract['inverse_fragments']:
                old=item['merged_fragment']
                for changed in [raw.replace(old,'',1),raw+old]:
                    with self.assertRaises(AssertionError):normalize_539_parent(key,changed)
        read=Path.read_bytes;altered=read(fixture)+b' '
        with patch.object(Path,'read_bytes',lambda p,*a,**k:altered if p==fixture else read(p,*a,**k)):
            with self.assertRaises(AssertionError):normalize(next(iter(data['contracts'])),'')
    def test_unreviewed_added_files_fail_closed(self):
        with self.assertRaises(AssertionError):approved_original_file('AteTests/Unreviewed.swift',b'')
    def test_mutations_fail_through_original_frozen_guard_methods(self):
        import importlib
        cases=[('test_qa8_detail_layout','DetailLayoutCaptureTests','test_no_test_or_logic_or_budget_edits','AteTests/AppStoreWriterBoundaryTests.swift','XCTAssertTrue(', 'XCTAssertFalse('),
               ('test_qa8_detail_layout','DetailLayoutCaptureTests','test_no_test_or_logic_or_budget_edits','AteTests/UserDataSyncTests.swift','XCTAssertNil(oldContainer', 'XCTAssertNotNil(oldContainer'),
               ('test_qa8_detail_layout','DetailLayoutCaptureTests','test_no_test_or_logic_or_budget_edits','AteTests/CookPlanAccountSafetyTests.swift','XCTAssertEqual(', 'XCTAssertNotEqual('),
               ('test_settings_clear_band','SettingsClearBandTests','test_entire_ui_file_reconstructs_exact_d994_original','AteUITests/CoverageUITests.swift','.swipeUp()', '.swipeDown()'),
               ('test_menu_favourite_capture','MenuFavouriteCaptureTests','test_original_file_3_unchanged','.github/workflows/dogfood-qualification.yml','-default-test-execution-time-allowance 240','-default-test-execution-time-allowance 999')]
        read,binary=Path.read_text,Path.read_bytes
        for mod,cls,method,file,old,new in cases:
            target=ROOT/file;original=read(target);self.assertIn(old,original);changed=original.replace(old,new,1)
            with patch.object(Path,'read_text',lambda p,*a,**kw:changed if p==target else read(p,*a,**kw)), patch.object(Path,'read_bytes',lambda p,*a,**kw:changed.encode() if p==target else binary(p,*a,**kw)):
                case=getattr(importlib.import_module(mod),cls)(method)
                with self.assertRaises(AssertionError):getattr(case,method)()
