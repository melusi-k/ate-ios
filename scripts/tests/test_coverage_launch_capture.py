from approved_merge_composed import normalize
from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[2]
def restore_coverage_workflow(s):
    s=s.replace('            cook-completion-window\n            coverage-launch-lifecycle\n','            cook-completion-window\n',1)
    s=s.replace('            CODE_SIGNING_ALLOWED=NO > cook-finish-accessory.log 2>&1 || coverage_status=$?\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/end-utc.txt\n          stop_coverage_lifecycle\n          trap - EXIT\n          python3 scripts/capture-coverage-launch-window.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle || echo \'Coverage launch log collector failed; qualification status unchanged.\'\n          # Metadata and test markers survive an artifact DNS failure in this job log.\n          tail -5 coverage-launch-lifecycle/process-metadata.jsonl || true\n          grep -F \'COVERAGE-LAUNCH\' cook-finish-accessory.log || true\n          if [ "$coverage_status" -ne 0 ]; then tail -120 cook-finish-accessory.log; exit 1; fi','            CODE_SIGNING_ALLOWED=NO > cook-finish-accessory.log 2>&1 || { tail -120 cook-finish-accessory.log; exit 1; }',1)
    s=s.replace('          mkdir -p coverage-launch-lifecycle\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/start-utc.txt\n          python3 scripts/capture-cookplan-process-lifecycle.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle > coverage-launch-lifecycle/collector-status.txt 2>&1 &\n          coverage_lifecycle_pid=$!\n          stop_coverage_lifecycle() {\n            kill "$coverage_lifecycle_pid" 2>/dev/null || true\n            wait "$coverage_lifecycle_pid" || true\n          }\n          trap stop_coverage_lifecycle EXIT\n          coverage_status=0\n          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/CookFinishAccessoryUITests','          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/CookFinishAccessoryUITests',1)
    return s

class CoverageLaunchContracts(unittest.TestCase):
    def test_original_file_0_unchanged(self):
        s=normalize('source:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_text())
        from test_relay_return_capture import restore_relay_return_capture
        s=restore_relay_return_capture(self,s,'AteUITests/CoverageUITests.swift')
        from test_about_targeting import restore_about_targeting
        s=restore_about_targeting(self,s)
        self.assertEqual(s.count('    func testBottomBarsDoNotOverlapRecipeDetail() {\n        captureCoverageLaunch = true\n        defer { captureCoverageLaunch = false }\n        launch(["-simulateOffline"])\n        coverageLaunchMark("body-after-launch")'),1)
        s=s.replace('    func testBottomBarsDoNotOverlapRecipeDetail() {\n        captureCoverageLaunch = true\n        defer { captureCoverageLaunch = false }\n        launch(["-simulateOffline"])\n        coverageLaunchMark("body-after-launch")','    func testBottomBarsDoNotOverlapRecipeDetail() {\n        launch(["-simulateOffline"])',1)
        self.assertEqual(s.count('        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra\n        if captureCoverageLaunch {\n            coverageLaunchMark("before-pixels")\n            shot("coverage-launch-before-original-call")\n            coverageLaunchMark("launch-enter")\n        }\n        defer {\n            if captureCoverageLaunch {\n                coverageLaunchMark("launch-scope-exit")\n                shot("coverage-launch-scope-exit")\n            }\n        }\n        app.launch()\n        coverageLaunchMark("launch-return")\n        return app'),1)
        s=s.replace('        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra\n        if captureCoverageLaunch {\n            coverageLaunchMark("before-pixels")\n            shot("coverage-launch-before-original-call")\n            coverageLaunchMark("launch-enter")\n        }\n        defer {\n            if captureCoverageLaunch {\n                coverageLaunchMark("launch-scope-exit")\n                shot("coverage-launch-scope-exit")\n            }\n        }\n        app.launch()\n        coverageLaunchMark("launch-return")\n        return app','        app = XCUIApplication(); app.launchArguments = ["-UITesting"] + extra; app.launch(); return app',1)
        self.assertEqual(s.count('    private var captureCoverageLaunch = false\n    private func coverageLaunchMark(_ phase: String) {\n        guard captureCoverageLaunch else { return }\n        print("COVERAGE-LAUNCH phase=\\(phase) uptime=\\(ProcessInfo.processInfo.systemUptime)")\n    }\n\n    @discardableResult\n    func launch'),1)
        s=s.replace('    private var captureCoverageLaunch = false\n    private func coverageLaunchMark(_ phase: String) {\n        guard captureCoverageLaunch else { return }\n        print("COVERAGE-LAUNCH phase=\\(phase) uptime=\\(ProcessInfo.processInfo.systemUptime)")\n    }\n\n    @discardableResult\n    func launch','    @discardableResult\n    func launch',1)
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'d0d4a8761d0dd7a1d833d8ad7e0d0d45e6a9ec04ec2913c7f3482f3b1ef4922a')
    def test_original_file_1_unchanged(self):
        s=normalize('source:.github/workflows/compile-check.yml', (ROOT/'.github/workflows/compile-check.yml').read_text())
        from test_relay_return_capture import restore_relay_return_capture
        s=restore_relay_return_capture(self,s,'.github/workflows/compile-check.yml')
        self.assertEqual(s.count('            cook-completion-window\n            coverage-launch-lifecycle\n'),1)
        s=s.replace('            cook-completion-window\n            coverage-launch-lifecycle\n','            cook-completion-window\n',1)
        self.assertEqual(s.count('            CODE_SIGNING_ALLOWED=NO > cook-finish-accessory.log 2>&1 || coverage_status=$?\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/end-utc.txt\n          stop_coverage_lifecycle\n          trap - EXIT\n          python3 scripts/capture-coverage-launch-window.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle || echo \'Coverage launch log collector failed; qualification status unchanged.\'\n          # Metadata and test markers survive an artifact DNS failure in this job log.\n          tail -5 coverage-launch-lifecycle/process-metadata.jsonl || true\n          grep -F \'COVERAGE-LAUNCH\' cook-finish-accessory.log || true\n          if [ "$coverage_status" -ne 0 ]; then tail -120 cook-finish-accessory.log; exit 1; fi'),1)
        s=s.replace('            CODE_SIGNING_ALLOWED=NO > cook-finish-accessory.log 2>&1 || coverage_status=$?\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/end-utc.txt\n          stop_coverage_lifecycle\n          trap - EXIT\n          python3 scripts/capture-coverage-launch-window.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle || echo \'Coverage launch log collector failed; qualification status unchanged.\'\n          # Metadata and test markers survive an artifact DNS failure in this job log.\n          tail -5 coverage-launch-lifecycle/process-metadata.jsonl || true\n          grep -F \'COVERAGE-LAUNCH\' cook-finish-accessory.log || true\n          if [ "$coverage_status" -ne 0 ]; then tail -120 cook-finish-accessory.log; exit 1; fi','            CODE_SIGNING_ALLOWED=NO > cook-finish-accessory.log 2>&1 || { tail -120 cook-finish-accessory.log; exit 1; }',1)
        self.assertEqual(s.count('          mkdir -p coverage-launch-lifecycle\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/start-utc.txt\n          python3 scripts/capture-cookplan-process-lifecycle.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle > coverage-launch-lifecycle/collector-status.txt 2>&1 &\n          coverage_lifecycle_pid=$!\n          stop_coverage_lifecycle() {\n            kill "$coverage_lifecycle_pid" 2>/dev/null || true\n            wait "$coverage_lifecycle_pid" || true\n          }\n          trap stop_coverage_lifecycle EXIT\n          coverage_status=0\n          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/CookFinishAccessoryUITests'),1)
        s=s.replace('          mkdir -p coverage-launch-lifecycle\n          date -u \'+%Y-%m-%d %H:%M:%S\' > coverage-launch-lifecycle/start-utc.txt\n          python3 scripts/capture-cookplan-process-lifecycle.py --sim-id "$SIM_ID" --output coverage-launch-lifecycle > coverage-launch-lifecycle/collector-status.txt 2>&1 &\n          coverage_lifecycle_pid=$!\n          stop_coverage_lifecycle() {\n            kill "$coverage_lifecycle_pid" 2>/dev/null || true\n            wait "$coverage_lifecycle_pid" || true\n          }\n          trap stop_coverage_lifecycle EXIT\n          coverage_status=0\n          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/CookFinishAccessoryUITests','          xcodebuild test-without-building -project Ate.xcodeproj -scheme Ate -destination "id=$SIM_ID" \\\n            -only-testing:AteUITests/CookFinishAccessoryUITests',1)
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'84e7f47241bb46dffde2d9d65f0c722d5228ccb625fd072267c19e71a273aeb0')

class CoverageLaunchCollectorTests(unittest.TestCase):
    def test_bounded_read_only_commands(self):
        import importlib.util,tempfile
        from unittest.mock import patch
        spec=importlib.util.spec_from_file_location('coverage_capture',ROOT/'scripts/capture-coverage-launch-window.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            (out/'start-utc.txt').write_text('2026-11-15 06:33:02')
            (out/'end-utc.txt').write_text('2026-11-15 06:39:16')
            with patch.object(mod.subprocess,'run') as run:
                run.return_value.returncode=0
                mod.capture('sim-id',out)
                self.assertEqual(run.call_count,2)
                for call in run.call_args_list:
                    command=call.args[0]
                    self.assertIn('show',command)
                    self.assertIn('--start',command)
                    self.assertEqual(call.kwargs['timeout'],15)
                    self.assertNotIn('terminate',command)
                    self.assertNotIn('launch',command)
    def test_no_new_ax_reads_or_mutations(self):
        s=normalize('source:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_text())
        capture=s.split('private var captureCoverageLaunch')[1].split('    func shot(')[0]
        for token in ['.state','.exists','.processID','waitForExistence','terminate()']:
            self.assertNotIn(token,capture)
