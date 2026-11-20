"""Separate Dogfood jobs retain exact required cases and never launder failures."""
from collections import Counter
from pathlib import Path
import copy,importlib.util,json,os,re,subprocess,tempfile,unittest,yaml
ROOT=Path(__file__).resolve().parents[2]
def load(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
VERIFY=load('dogfood_group','verify-dogfood-group.py');GATE=load('dogfood_gate','ci-dogfood-gate.py')
def tree(group):return {'testNodes':[{'nodeType':'Test Case','nodeIdentifier':name+'()','result':'Passed'} for name in VERIFY.GROUPS[group]]}
def log(group):
 lines=["Test Case '-[AteUITests."+name.split('/')[0]+' '+name.split('/')[1]+"]' passed (1 seconds)." for name in VERIFY.GROUPS[group]]
 return '\n'.join(lines)+'\nExecuted '+str(len(VERIFY.GROUPS[group]))+' tests, with 0 failures (0 unexpected) in 1 seconds\n** TEST SUCCEEDED **\n'
class IndependentDogfoodTests(unittest.TestCase):
 def test_exact_groups_and_every_native_pass(self):
  self.assertEqual([len(VERIFY.GROUPS[g]) for g in ['qa','library']],[9,3])
  self.assertEqual(len(set(VERIFY.GROUPS['qa']+VERIFY.GROUPS['library'])),12)
  for group in VERIFY.GROUPS:self.assertEqual(VERIFY.validate(log(group),group,tree(group)),sorted(VERIFY.GROUPS[group]))
 def test_nonzero_or_signal_never_passes_even_with_success_evidence(self):
  for rc in [1,65,124,-15,-9]:
   with self.assertRaises(ValueError):VERIFY.validate(log('qa'),'qa',tree('qa'),rc)
 def test_allowance_failure_and_contradictory_pass_text_stay_red(self):
  for extra in ['Test Case xyz failed','test exceeded execution time allowance of 4 minutes','Fatal error: overflow','Testing failed:','** TEST FAILED **','Executed 9 tests, with 1 failure (0 unexpected) in 1 seconds']:
   with self.assertRaises(ValueError):VERIFY.validate(extra+'\n'+log('qa'),'qa',tree('qa'))
  for bad in ['',log('qa').replace('** TEST SUCCEEDED **','prefix ** TEST SUCCEEDED ** suffix'),log('qa').replace('9 tests','8 tests')]:
   with self.assertRaises(ValueError):VERIFY.validate(bad,'qa',tree('qa'))
 def test_missing_extra_duplicate_failed_skipped_and_malformed_results_refuse(self):
  for group in VERIFY.GROUPS:
   source=tree(group)
   variants=[{}, {'testNodes':[]}, {'testNodes':[None]}]
   for result in ['Failed','Skipped','Unknown']:
    v=copy.deepcopy(source);v['testNodes'][0]['result']=result;variants.append(v)
   for mutation in ['missing','extra','duplicate','wrong-name']:
    v=copy.deepcopy(source)
    if mutation=='missing':v['testNodes'].pop()
    elif mutation=='extra':v['testNodes'].append({'nodeType':'Test Case','nodeIdentifier':'Unexpected/test','result':'Passed'})
    elif mutation=='duplicate':v['testNodes'].append(v['testNodes'][0])
    else:v['testNodes'][0]['nodeIdentifier']='Wrong/test'
    variants.append(v)
   for value in variants:
    with self.assertRaises(ValueError):VERIFY.validate(log(group),group,value)
 def test_both_source_receipts_required_no_quarantine_substitute(self):
  sha='a'*40;needs={x:{'result':'success','outputs':{'sha':sha}} for x in ['pin-source',*GATE.LANES]};needs['changes']={'result':'success','outputs':{'app':'true'}}
  self.assertEqual(GATE.validate(sha,needs),['qa-critical-flows','library-popup'])
  for lane in GATE.LANES:
   for status in ['failure','cancelled','skipped','timed_out','']:
    v=copy.deepcopy(needs);v[lane]['result']=status;v['sync-quarantine']={'result':'success','outputs':{'sha':sha}}
    with self.assertRaises(ValueError):GATE.validate(sha,v)
   v=copy.deepcopy(needs);v[lane]['outputs']['sha']='b'*40
   with self.assertRaises(ValueError):GATE.validate(sha,v)
 def test_independent_jobs_keep_caps_and_aggregate_context(self):
  source=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text();jobs=yaml.safe_load(source)['jobs']
  self.assertNotIn('concurrency:',source)
  self.assertEqual(jobs['dogfood-qualification']['needs'],['changes','pin-source','qa-critical-flows','library-popup'])
  for lane,group in [('qa-critical-flows','qa'),('library-popup','library')]:
   j=jobs[lane];self.assertEqual(j['runs-on'],'xcode-27');self.assertEqual(j['timeout-minutes'],60);self.assertEqual(j['needs'],['changes','pin-source'])
   steps=j['steps'];test=next(s for s in steps if s.get('id')=='critical_flows');self.assertEqual(test['timeout-minutes'],30)
   self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',test['run'])
   self.assertIn('--group '+group,test['run']);self.assertIn('exit 1;',test['run']);self.assertNotIn('continue-on-error',test)
   selected=re.findall(r'-only-testing:AteUITests/([^\s\\]+)',test['run']);self.assertEqual(selected,VERIFY.GROUPS[group])
   self.assertEqual(j['outputs']['sha'],'${{ steps.receipt.outputs.sha }}')
   self.assertEqual(steps[-1]['with']['if-no-files-found'],'error')
   checkout=next(s for s in steps if s.get('uses','').startswith('actions/checkout@'));self.assertEqual(checkout['with']['ref'],'${{ needs.pin-source.outputs.sha }}');self.assertEqual(checkout['with']['fetch-depth'],0)
   self.assertIn('mkdir -p build',str(steps));self.assertIn('SIM_ID=',test['run'])
  q=next(s for s in jobs['sync-quarantine']['steps'] if s.get('id')=='sync_quarantine')
  self.assertEqual(q['timeout-minutes'],15);self.assertTrue(q['continue-on-error']);self.assertIn('testQA7_SyncAccount',q['run'])
  self.assertIn('name: Dogfood qualification result',source)
 def test_all_original_selected_cases_and_native_flags_preserved(self):
  from dogfood_independent_lane_delta import restore
  path='.github/workflows/dogfood-qualification.yml';s=(ROOT/path).read_text();old=restore(path,s)
  self.assertEqual(Counter(re.findall(r'-only-testing:([^\s\\]+)',s)),Counter(re.findall(r'-only-testing:([^\s\\]+)',old)))
  before=yaml.safe_load(old)['jobs']['dogfood-qualification'];after=yaml.safe_load(s)['jobs']
  critical=next(x['run'] for x in before['steps'] if x.get('id')=='critical_flows')
  def invocation(body):
   text=body[body.index('xcodebuild test -project'):body.index(' > dogfood-critical-flows')]
   text='\n'.join(l for l in text.splitlines() if '-only-testing:' not in l)
   return re.sub('DogfoodCriticalFlows-(qa|library)','DogfoodCriticalFlows',text)
  for lane in GATE.LANES:
   body=next(x['run'] for x in after[lane]['steps'] if x.get('id')=='critical_flows')
   self.assertEqual(invocation(body),invocation(critical))
  original=next(x['run'] for x in before['steps'] if x.get('id')=='sync_quarantine')
  moved=next(x['run'] for x in after['sync-quarantine']['steps'] if x.get('id')=='sync_quarantine')
  self.assertEqual(original,moved)
 def test_every_shell_step_parses(self):
  for job in yaml.safe_load((ROOT/'.github/workflows/dogfood-qualification.yml').read_text())['jobs'].values():
   for step in job.get('steps',[]):
    if 'run' in step:
     value=subprocess.run(['bash','-n'],input=step['run'],text=True,capture_output=True);self.assertEqual(value.returncode,0,value.stderr)
 def test_real_native_step_failure_cannot_reach_success_receipt(self):
  workflow=yaml.safe_load((ROOT/'.github/workflows/dogfood-qualification.yml').read_text())['jobs']
  for lane,group in [('qa-critical-flows','qa'),('library-popup','library')]:
   body=next(s['run'] for s in workflow[lane]['steps'] if s.get('id')=='critical_flows')
   body=re.sub(r'\$\{\{[^}]+\}\}','fake-sim',body)
   with tempfile.TemporaryDirectory() as d:
    root=Path(d);(root/'scripts').mkdir();(root/'build').mkdir();(root/'bin').mkdir()
    (root/'scripts/verify-dogfood-group.py').write_bytes((ROOT/'scripts/verify-dogfood-group.py').read_bytes())
    xcode=root/'bin/xcodebuild';xcode.write_text('#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\na=sys.argv\nPath(a[a.index("-resultBundlePath")+1]).mkdir(parents=True,exist_ok=True)\nprint(os.environ["NATIVE_LOG"])\nsys.exit(int(os.environ["NATIVE_EXIT"]))\n');xcode.chmod(0o755)
    xcrun=root/'bin/xcrun';xcrun.write_text('#!/usr/bin/env python3\nimport os,sys\nif "xcresulttool" in sys.argv:print(os.environ["NATIVE_TREE"])\n');xcrun.chmod(0o755)
    env=dict(os.environ,PATH=str(root/'bin')+':'+os.environ['PATH'],NATIVE_LOG=log(group),NATIVE_TREE=json.dumps(tree(group)))
    for rc in [65,124,-15,0]:
     env['NATIVE_EXIT']=str(rc);run=subprocess.run(['bash','-c',body],cwd=root,env=env,text=True,capture_output=True)
     self.assertEqual(run.returncode==0,rc==0,(group,rc,run.stdout,run.stderr))
     if rc!=0:self.assertFalse((root/('dogfood-critical-flows-'+group+'.log.verified.json')).exists())
     for p in root.glob('dogfood-critical-flows-*.log.verified.json'):p.unlink()
 def test_pinned_inverse_refuses_unrelated_missing_and_duplicate_edits(self):
  from dogfood_independent_lane_delta import restore
  fixture=json.loads((ROOT/'scripts/tests/dogfood_independent_lane_inverse.json').read_text())
  for path,c in fixture.items():
   s=(ROOT/path).read_text();self.assertTrue(restore(path,s))
   for fragment in c['fragments']:
    for changed in [s.replace(fragment['new'],'',1),s+fragment['new'],s+'# unrelated\n']:
     with self.assertRaises(AssertionError):restore(path,changed)
