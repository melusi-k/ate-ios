from approved_merge_composed import normalize
from pathlib import Path
from test_coverage_launch_capture import restore_coverage_workflow
import unittest,hashlib,importlib.util,yaml,subprocess
ROOT=Path(__file__).resolve().parents[2]
class CookPlanProcessLifecycleTests(unittest.TestCase):
    def test_metadata_filter(self):
        spec=importlib.util.spec_from_file_location('capture',ROOT/'scripts/capture-cookplan-process-lifecycle.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        self.assertEqual(mod.filter_launchctl('24788 0 UIKitApplication:com.melusik.ate[uuid]\n- -9 com.apple.testmanagerd\n1 0 secret-label\n'),[{'pid':24788,'status':0,'category':'ate'},{'pid':None,'status':-9,'category':'testmanagerd'}])
    def test_workflow_only_capture_changes(self):
        from test_relay_return_capture import restore_relay_return_capture
        s=restore_coverage_workflow(restore_relay_return_capture(self,normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text()),'.github/workflows/compile-check.yml'))
        s=s.replace('            nutrition-ui-tests.log\n            cookplan-process-lifecycle\n','            nutrition-ui-tests.log\n')
        s=s.replace('          stop_lifecycle\n          trap - EXIT\n          # Export screenshots, hierarchy snapshots and audit attachments on every outcome,','          # Export screenshots, hierarchy snapshots and audit attachments on every outcome,')
        s=s.replace('          mkdir -p cookplan-process-lifecycle\n          python3 scripts/capture-cookplan-process-lifecycle.py --sim-id "$SIM_ID" --output cookplan-process-lifecycle > cookplan-process-lifecycle/collector-status.txt 2>&1 &\n          lifecycle_pid=$!\n          stop_lifecycle() {\n            kill "$lifecycle_pid" 2>/dev/null || true\n            wait "$lifecycle_pid" || true\n          }\n          trap stop_lifecycle EXIT\n          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/NutritionDiaryUITests','          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/NutritionDiaryUITests')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'c93dc293674a208c1a6dd75c71c42be0f9abc4311b3f72ecbb926277775397ed')
        w=yaml.safe_load(normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text()))
        for job in w['jobs'].values():
            for step in job.get('steps',[]):
                if 'stop_lifecycle' in step.get('run',''):
                    subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
