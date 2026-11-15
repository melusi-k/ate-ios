from pathlib import Path
import re,subprocess,unittest,yaml
ROOT=Path(__file__).resolve().parents[2]
class DogfoodStepPartitionTests(unittest.TestCase):
    def test_budget_and_exact_selector_partition(self):
        text=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        original=['AteUITests/KeyFlowsQATests/testQA1_AddFromURL_JSONLD', 'AteUITests/KeyFlowsQATests/testQA1_AddFromURL_InstagramCaption', 'AteUITests/KeyFlowsQATests/testQA1_AddFromURL_HiddenCaptionFallback', 'AteUITests/KeyFlowsQATests/testQA2_AddFromPhoto', 'AteUITests/KeyFlowsQATests/testQA3_GenerateAndEdit', 'AteUITests/KeyFlowsQATests/testQA4_Save', 'AteUITests/KeyFlowsQATests/testQA5_Share', 'AteUITests/KeyFlowsQATests/testQA6_OpenShared', 'AteUITests/KeyFlowsQATests/testQA8_Timers', 'AteUITests/AteUITests/test28_GroupSortAndMenus', 'AteUITests/AteUITests/test29_ReorderMyOrder', 'AteUITests/AteUITests/test29b_ReorderMyOrderActions']
        job=yaml.safe_load(text)['jobs']['dogfood-qualification']
        self.assertEqual(job['runs-on'],'xcode-27')
        self.assertEqual(job['timeout-minutes'],60)
        steps={s['id']:s for s in job['steps'] if 'id' in s}
        library=steps['library_flows'];qa=steps['critical_flows']
        self.assertEqual(library['timeout-minutes'],12)
        self.assertEqual(qa['timeout-minutes'],18)
        selected=[]
        for step in [library,qa]:
            self.assertIn("always() && steps.build_tests.outcome == 'success'",step['if'])
            self.assertNotIn('continue-on-error',step)
            self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',step['run'])
            self.assertIn('-parallel-testing-enabled NO',step['run'])
            selectors=re.findall(r'-only-testing:(\S+)',step['run']);selected+=selectors
            for selector in selectors:
                cls,method=selector.split('/')[1:]
                self.assertIn(cls+' '+method+"]' passed",step['run'])
        self.assertCountEqual(selected,original)
        self.assertEqual(len(set(selected)),12)
        self.assertEqual(text.count('xcodebuild build-for-testing '),1)
        self.assertEqual(text.count('xcodebuild test-without-building '),3)
        self.assertNotIn('xcodebuild test -',text)
        self.assertEqual(steps['sync_quarantine']['timeout-minutes'],15)
        self.assertTrue(steps['sync_quarantine']['continue-on-error'])
        self.assertIn('QA6/QA8 durations unmeasured',text)
        self.assertNotIn('-retry',text)
        for step in job['steps']:
            if 'run' in step:subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
    def test_aggregate_enforcement_requires_all_results(self):
        job=yaml.safe_load((ROOT/'.github/workflows/dogfood-qualification.yml').read_text())['jobs']['dogfood-qualification']
        gate=next(s for s in job['steps'] if s.get('name')=='Enforce all twelve required Dogfood passes')
        self.assertEqual(gate['if'],'always()')
        self.assertIn('"$BUILD_OUTCOME" != success',gate['run'])
        self.assertIn('"$LIBRARY_OUTCOME" != success',gate['run'])
        self.assertIn('"$QA_OUTCOME" != success',gate['run'])
        self.assertIn('"$total" -lt 12',gate['run'])
