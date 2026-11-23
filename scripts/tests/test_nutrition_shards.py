"""Real workflow semantics, with executable fail-closed aggregate mutants."""
import itertools,json,re,subprocess,unittest
from pathlib import Path
import yaml
from nutrition_shards_delta import restore
ROOT=Path(__file__).resolve().parents[2]
PATH='.github/workflows/compile-check.yml'
class NutritionShardTests(unittest.TestCase):
    def setUp(self):
        self.raw=(ROOT/PATH).read_text()
        self.jobs=yaml.safe_load(self.raw)['jobs']
        self.old=restore(PATH,self.raw)
        self.baseline=json.loads((ROOT/'scripts/tests/nutrition_shards_baseline.json').read_text())
    def test_exact_selector_union_and_empty_intersections(self):
        rows=self.jobs['nutrition-ui']['strategy']['matrix']['include']
        self.assertEqual([r['shard'] for r in rows],['cookplan','diary','goals'])
        selections=[set(re.findall(r'-only-testing:(\S+)',r['selectors'])) for r in rows]
        self.assertEqual(set.union(*selections),set(self.baseline['selectors']))
        for a,b in itertools.combinations(selections,2):self.assertFalse(a&b)
        self.assertEqual(sum(map(len,selections)),len(self.baseline['selectors']))
        guards=[g for r in rows for g in r['named_passes'].splitlines()]
        self.assertCountEqual(guards,self.baseline['guards'])
        self.assertEqual(len(guards),len(set(guards)))
    def test_worker_policy_and_exact_head(self):
        ui=self.jobs['nutrition-ui']
        self.assertEqual(ui['strategy']['max-parallel'],1)
        self.assertIs(ui['strategy']['fail-fast'],False)
        for key in ['nutrition-units','nutrition-ui']:
            job=self.jobs[key];self.assertEqual(job['timeout-minutes'],45)
            checkout=next(s for s in job['steps'] if s.get('uses','').startswith('actions/checkout@'))
            self.assertEqual(checkout['with']['ref'],'${{ github.event.pull_request.head.sha || github.sha }}')
            self.assertEqual(checkout['with']['fetch-depth'],0)
        self.assertEqual(self.raw.count('-only-testing:AteTests \\'),1)
        for key in ['nutrition-units','nutrition-ui']:
            run='\n'.join(s.get('run','') for s in self.jobs[key]['steps'])
            self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',run)
            self.assertNotIn('-retry-tests-on-failure',run)
            self.assertNotIn('-test-iterations',run)
            self.assertNotIn('-skip-testing:',run)
    def test_units_clip_and_required_verifier_once(self):
        self.assertEqual(self.raw.count('-scheme AteClip -destination'),2)
        self.assertEqual(self.raw.count('python3 scripts/verify-full-unit-required.py full-unit-tests.json scripts/full-unit-required.txt'),1)
        oldjobs=yaml.safe_load(self.old)['jobs'];before=oldjobs['build-nutrition']['steps']
        after=self.jobs['nutrition-units']['steps']
        for name in ['Build isolated App Clip target','Run App Clip URL contract tests','Full exact-head unit suite (all AteTests)']:
            self.assertEqual(next(s for s in before if s.get('name')==name),next(s for s in after if s.get('name')==name))
        uploads=[s for s in after if s.get('uses','').startswith('actions/upload-artifact@')]
        self.assertTrue(any('app-clip-tests.xcresult' in s['with']['path'] and s['if']=='always()' for s in uploads))
    def test_aggregate_executes_and_refuses_every_non_success(self):
        job=self.jobs['build-nutrition']
        self.assertEqual(job['needs'],['changes','nutrition-units','nutrition-ui'])
        self.assertEqual(job['if'],"${{ always() && needs.changes.outputs.app == 'true' }}")
        script=job['steps'][0]['run']
        for units,ui in itertools.product(['success','failure','cancelled','skipped','','unknown'],repeat=2):
            r=subprocess.run(['bash','-c',script],env={'UNITS_RESULT':units,'UI_RESULT':ui},capture_output=True)
            self.assertEqual(r.returncode==0,units==ui=='success',(units,ui))
        oldjobs=yaml.safe_load(self.old)['jobs']
        for key in ['compile','qualification-result','docs-validation']:
            self.assertEqual(self.jobs[key],oldjobs[key])
    def test_immediate_cookplan_artifacts_and_visible_export_failure(self):
        steps=self.jobs['nutrition-ui']['steps']
        test=next(s for s in steps if s.get('name')=='Nutrition diary and goals UI regressions (#179)')
        self.assertIn('nutrition-ui-exit-status.txt',test['run'])
        self.assertIn('exit 1',test['run'])
        export=next(s for s in steps if s.get('name')=='Export shard xcresult attachments')
        self.assertIn('always()',export['if']);self.assertIn('exit "$status"',export['run'])
        self.assertIn('::error::',export['run'])
        ledger=next(s for s in steps if s.get('name')=='Retain CookPlan cancel phase ledger')
        self.assertIn("matrix.shard == 'cookplan'",ledger['if'])
        upload=next(s for s in steps if s.get('name')=='Upload nutrition UI diagnostics (early)')
        self.assertEqual(upload['if'],'always()')
        for token in ['nutrition-ui-tests.log','nutrition-ui-exit-status.txt','nutrition-export-status.log','cook-plan-cancel-live-query','nutrition-ui-tests.xcresult']:
            self.assertIn(token,upload['with']['path'])
        self.assertEqual(steps[-1],upload)
    def test_all_generated_bash_bodies_parse(self):
        for key in ['nutrition-units','nutrition-ui','build-nutrition']:
            for step in self.jobs[key]['steps']:
                if 'run' in step:
                    r=subprocess.run(['bash','-n'],input=step['run'],capture_output=True,text=True)
                    self.assertEqual(r.returncode,0,(key,step.get('name'),r.stderr))
    def test_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        self.assertEqual(restore(PATH,self.old),self.old)
        for mutant in [self.raw+'\n# unrelated',self.raw.replace('max-parallel: 1','max-parallel: 2',1),self.raw+self.raw,self.raw[:-1]]:
            with self.assertRaises(AssertionError):restore(PATH,mutant)
