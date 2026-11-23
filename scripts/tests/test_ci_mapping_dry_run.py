"""Mapping is read-only evidence, never permission to skip existing checks."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ci_mapping',ROOT/'scripts/ci-mapping.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)

class CIMappingDryRunTests(unittest.TestCase):
    def setUp(self):
        self.inv=M.inventory(ROOT)
        self.manifest=json.loads((ROOT/'ci/test-area-map.json').read_text())
    def plan(self,diff,manifest=None,trusted=True):
        return M.resolve(manifest or self.manifest,self.inv,diff,'a'*40,'b'*40,trusted)
    def test_inventory_matches_all_current_source_declarations(self):
        stored=json.loads((ROOT/'ci/test-inventory.json').read_text())
        self.assertEqual(self.inv,stored)
        self.assertFalse(self.inv['errors'])
        ids=[e['selector'] for e in self.inv['entries']]
        self.assertEqual(len(ids),len(set(ids)))
        for target in M.ROOTS:
            self.assertTrue(any(i.startswith(target+'/') for i in ids))
    def test_every_manifest_selector_exists_and_every_native_test_path_is_mapped(self):
        available={e['selector'] for e in self.inv['entries']}
        for record in self.manifest['areas'].values():
            self.assertTrue(record['selectors'])
            self.assertEqual(len(record['selectors']),len(set(record['selectors'])))
            self.assertTrue(set(record['selectors'])<=available)
        for e in self.inv['entries']:
            if e['kind']=='native':
                self.assertTrue(any(e['path'] in r['paths'] and e['selector'] in r['selectors']
                                    for r in self.manifest['areas'].values()),e)
    def test_unknown_empty_and_bootstrap_fall_back_without_empty_success(self):
        for diff,trusted in [([],True),([{'path':'unmapped/new.bin','status':'A'}],True),
                             ([{'path':'Ate/Logic/CookPlan.swift','status':'M'}],False)]:
            p=self.plan(diff,trusted=trusted)
            self.assertEqual(p['mapping_gate'],'review_required')
            self.assertTrue(p['selectors'])
            self.assertFalse(p['authorizes_narrowing'])
            self.assertEqual(p['qualification'],'NOT RUN; existing gates unchanged')
    def test_rename_and_delete_keep_old_area_and_new_area_union(self):
        p=self.plan([{'path':'Ate/Views/ExploreView.swift','previous_path':'Ate/Views/CookPlanSheet.swift','status':'R100'}])
        self.assertTrue({'generation','cookplan'}<=set(p['areas']))
        deleted=self.plan([{'path':'Ate/Views/CookPlanSheet.swift','status':'D'}])
        self.assertIn('cookplan',deleted['areas'])
        self.assertTrue(set(self.manifest['areas']['cookplan']['selectors'])<=set(p['selectors']))
    def test_missing_duplicate_empty_or_deleted_selector_is_not_accepted(self):
        for change in ['unknown','empty','duplicate']:
            m=copy.deepcopy(self.manifest);r=m['areas']['cookplan']
            if change=='unknown':r['selectors'].append('AteTests/NoSuchClass/testMissing')
            elif change=='empty':r['selectors']=[]
            else:r['selectors'].append(r['selectors'][0])
            p=self.plan([{'path':'Ate/Logic/CookPlan.swift','status':'M'}],m)
            self.assertEqual(p['mapping_gate'],'review_required')
            self.assertTrue(p['fallback'])
    def test_self_weakening_mapping_workflow_and_shared_changes_are_conservative(self):
        for path in ['ci/test-area-map.json','scripts/ci-mapping.py','.github/workflows/compile-check.yml','Ate/Store/AppStore.swift']:
            p=self.plan([{'path':path,'status':'M'}])
            self.assertTrue(p['fallback'],path)
            self.assertFalse(p['authorizes_narrowing'])
    def test_full_sha_binding_and_rename_diff(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            def g(*a):return subprocess.check_output(['git','-C',tmp,*a]).decode().strip()
            g('init','-q');g('config','user.email','test@example.invalid');g('config','user.name','Test')
            (root/'old.txt').write_text('preserved\n');g('add','.');g('commit','-qm','base');base=g('rev-parse','HEAD')
            (root/'old.txt').rename(root/'new.txt');g('add','-A');g('commit','-qm','rename');head=g('rev-parse','HEAD')
            ancestor,diff=M.changes(root,base,head)
            self.assertEqual(ancestor,base);self.assertEqual(diff[0]['previous_path'],'old.txt')
            self.assertEqual(diff[0]['path'],'new.txt')
            with self.assertRaises(ValueError):M.changes(root,'main',head)
            with self.assertRaises(ValueError):M.changes(root,base,'HEAD')
    def test_workflow_executes_only_base_script_and_keeps_read_only_permissions(self):
        w=yaml.safe_load((ROOT/'.github/workflows/ci-mapping-dry-run.yml').read_text())
        self.assertEqual(w['permissions'],{'contents':'read'})
        job=w['jobs']['mapping-plan'];self.assertEqual(job['runs-on'],'ubuntu-latest')
        script=next(s['run'] for s in job['steps'] if s.get('name')=='Emit non-authorizing plan')
        self.assertIn('python3 trusted/scripts/ci-mapping.py',script)
        self.assertNotIn('python3 proposed/',script)
        self.assertNotIn('pull_request_target',(ROOT/'.github/workflows/ci-mapping-dry-run.yml').read_text())
        self.assertNotIn('secrets.',str(w));self.assertNotIn('xcodebuild',script)
        for s in job['steps']:
            if 'run' in s:self.assertEqual(subprocess.run(['bash','-n'],input=s['run'],text=True,capture_output=True).returncode,0)
    def test_no_worker_result_can_become_native_qualification(self):
        # This slice does not aggregate workers or emit any native success outcome.
        p=self.plan([{'path':'Ate/Logic/CookPlan.swift','status':'M'}])
        for result in ['success','failure','cancelled','missing','unallocated','export_failed']:
            annotated={**p,'future_worker_result':result}
            self.assertFalse(annotated['authorizes_narrowing'])
            self.assertIn('NOT RUN',annotated['qualification'])

    def test_candidate_inventory_new_or_deleted_test_invalidates_stored_inventory(self):
        changed=copy.deepcopy(self.inv)
        changed['entries']=changed['entries'][:-1]
        self.assertNotEqual(changed,json.loads((ROOT/'ci/test-inventory.json').read_text()))
        # Later cutover must treat any inventory drift as review, not hidden coverage loss.
        plan=self.plan([{'path':'AteTests/BrandNewTests.swift','status':'A'}])
        self.assertTrue(plan['fallback'])

    def test_manifest_plan_is_bound_to_both_revisions(self):
        p=self.plan([{'path':'Ate/Logic/CookPlan.swift','status':'M'}])
        self.assertEqual(p['base_sha'],'a'*40)
        self.assertEqual(p['head_sha'],'b'*40)
        q=M.resolve(self.manifest,self.inv,[{'path':'Ate/Logic/CookPlan.swift','status':'M'}],
                    'c'*40,'d'*40,True)
        self.assertNotEqual((p['base_sha'],p['head_sha']),(q['base_sha'],q['head_sha']))
