from pathlib import Path
import hashlib,json,unittest
from unittest.mock import patch
from approved_merge_523 import normalize
ROOT=Path(__file__).resolve().parents[2]
WORKFLOWS={'.github/workflows/aw-ci-coach.lock.yml': 'b919a6828d29373b7a3032b9af6f7f2ccf1927845fa1c9cc3c74fa7e1eaf58ec', '.github/workflows/aw-ci-coach.md': '1b5d9aaa1df1b08e5a4d60ee576c27769c333f82deaa451c335e6c4b929147dc', '.github/workflows/aw-ci-diagnosis.lock.yml': '8fcf326e6ff862e0f93424e380840833b42809b09fa6ac9e5ad691e632a2288b', '.github/workflows/aw-ci-diagnosis.md': '01df0a726a1659828b779bc405559dee91293b34c01689464cf55ec9cf4290f6', '.github/workflows/aw-daily-plan.lock.yml': 'fdb3ac60d2bea2a2f0031d3b77d7e07895cf55a14bef1ec0ca00da1610681341', '.github/workflows/aw-daily-plan.md': '3272ff7f8768f72a0c6640421ba98a7e3690807aceb8607064d7771a68c583c8', '.github/workflows/aw-daily-report.lock.yml': 'df948d1252db9c037589982cd7e38e18246be4a9ccc7db251d3aaf88154748cb', '.github/workflows/aw-daily-report.md': 'a740421a29c1ff3d2ea6d0ee67ef02eb1ae685f09e7ecd1cb0e602571efa3dd3', '.github/workflows/aw-doc-updater.lock.yml': '00274cd535f02c337eb2b0176a92bf6ff2640f1f7086844a38bd085689da8803', '.github/workflows/aw-doc-updater.md': '8289f95a348b956d99ff71ce00e3f7133abc05641feaecd9568f621c945f40b9', '.github/workflows/aw-focused-tests.lock.yml': 'ce1cae40ad0ed6e0b2eba87a9ddda3943a57ec82d1fea9fdd39eda1f7ce12f4e', '.github/workflows/aw-focused-tests.md': '34259fa848c4c83447827462fe15021e6424072c1905377a8183293b68099e73', '.github/workflows/aw-grumpy-reviewer.lock.yml': 'd2329f0ca4279e4b336bd0fe471f02e69eabfbfdb8f01d177a4cb0afa8c4ba63', '.github/workflows/aw-grumpy-reviewer.md': '487bce7a7171f3fad16d53d66876097c69990ae56f577a63ee234620b739ba72', '.github/workflows/aw-repository-assistant.lock.yml': '91913bf70f182007d8bbc342c5c202e7355f0563fec5e0308ecfab2f26cce083', '.github/workflows/aw-repository-assistant.md': '3e283e5b6fa0fc788790145c51e25b21d42ba1f7032eb2292d11dcce1fcb5369'}
NATIVE={'test28_GroupSortAndMenus': 'f70bcfcef2fed2b63cd2f090606fa42d92345abf1a16e52fb867fe9e3f4ce0d0', 'test29_ReorderMyOrder': '0def1973e1c3f85c8fc1ae663d7b5e204e143952ca0738e8eb3bd4261a614cdf', 'test29b_ReorderMyOrderActions': 'e215ebd66ff67836c74f54b8bdec2a0f3555459a142f6ca714b3d73015390d53'}
class Merge523Contracts(unittest.TestCase):
    def test_all_eight_workflow_sources_and_locks_byte_identical_and_off(self):
        for file,digest in WORKFLOWS.items():
            s=(ROOT/file).read_text();self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),digest,file)
            if file.endswith('.md'):self.assertIn('if: "false"',s)
    def test_one_prepare_in_source_order(self):
        s=(ROOT/'Ate/App/AteApp.swift').read_text()
        names=['ExploreRetentionQAFixtures.prepare(st)','CookJournalQARoute.prepare(st)','DogfoodSavedRecipeQAFixtures.prepare(st)']
        for name in names:self.assertEqual(s.count(name),1)
        self.assertEqual([s.index(name) for name in names],sorted(s.index(name) for name in names))
    def test_source_native_bodies_exact_and_required(self):
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        for name,digest in NATIVE.items():
            body=s.split('    func '+name+'() {',1)[1].split('\n    }',1)[0]
            self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),digest,name)
            for file in ['dogfood-qualification.yml','menu-qualification.yml']:
                self.assertIn('-only-testing:AteUITests/AteUITests/'+name,(ROOT/'.github/workflows'/file).read_text())
    def test_duplicate_missing_prepare_and_workflow_activation_mutants_fail(self):
        text=Path.read_text
        for file,old,new,method in [('Ate/App/AteApp.swift','DogfoodSavedRecipeQAFixtures.prepare(st)','DogfoodSavedRecipeQAFixtures.prepare(st); DogfoodSavedRecipeQAFixtures.prepare(st)',self.test_one_prepare_in_source_order),('Ate/App/AteApp.swift','DogfoodSavedRecipeQAFixtures.prepare(st)','',self.test_one_prepare_in_source_order),('.github/workflows/aw-ci-coach.md','if: "false"','if: "true"',self.test_all_eight_workflow_sources_and_locks_byte_identical_and_off)]:
            target=ROOT/file;raw=text(target);self.assertIn(old,raw);changed=raw.replace(old,new,1)
            with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==target else text(p,*a,**k)):
                with self.assertRaises(AssertionError):method()
    def test_original_ui_assertion_action_and_timeout_mutants_fail_original_guard(self):
        from test_add_title_query_diagnostic import AddTitleQueryDiagnosticTests
        target=ROOT/'AteUITests/AteUITests.swift';text=Path.read_text;raw=text(target)
        for old,new in [('XCTAssertTrue(','XCTAssertFalse('),('.tap()','.doubleTap()'),('timeout:','changedTimeout:')]:
            self.assertIn(old,raw);changed=raw.replace(old,new,1)
            with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==target else text(p,*a,**k)):
                with self.assertRaises(AssertionError):AddTitleQueryDiagnosticTests().test_all_original_tests_and_helpers_preserved()
    def test_inverse_count_mutants_fail_closed(self):
        data=json.loads((ROOT/'scripts/tests/approved_merge_523_inverses.json').read_text())
        for key,contract in data['contracts'].items():
            raw=(ROOT/contract['path']).read_text()
            for item in contract['inverse_fragments']:
                old=item['merged_fragment']
                for changed in [raw.replace(old,'',1),raw+old]:
                    with self.assertRaises(AssertionError):normalize(key,changed)
