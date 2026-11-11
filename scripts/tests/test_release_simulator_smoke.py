"""Release simulator budgets, proof gating and dedicated cache provenance."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/build-ipa.yml'


def steps():
    return re.split(r'(?=^      - (?:name:|uses:))', WORKFLOW.read_text(), flags=re.M)


def step(fragment):
    return next(s for s in steps() if fragment in s.splitlines()[0])


def script(fragment):
    text = step(fragment).split('        run: |\n', 1)[1]
    return '\n'.join(line[10:] if line.startswith('          ') else line for line in text.splitlines())


class ReleaseSimulatorSmokeTests(unittest.TestCase):
    def test_distinct_bounded_steps_and_no_ignored_failures(self):
        for name, identity in [('Simulator Release build (', 'simbuild'), ('Release smoke test (A-CI-03) - install', 'simsmoke')]:
            item = step(name)
            self.assertIn('id: ' + identity, item)
            self.assertIn('timeout-minutes: 20', item)
            self.assertNotIn('continue-on-error', item)
        self.assertNotIn('simctl install', script('Simulator Release build ('))
        self.assertNotIn('xcodebuild build', script('Release smoke test (A-CI-03) - install'))
        self.assertIn("success() && steps.simbuild.outcome == 'success'", step('Release smoke test (A-CI-03) - install'))

    def test_publish_requires_both_proofs(self):
        for name in ['Upload artifact', "Update rolling 'latest-build'", 'Published artifact smoke test (A-CI-06)']:
            condition = step(name).split('        if: ', 1)[1].splitlines()[0]
            for term in ['success()', "steps.simbuild.outcome == 'success'", "steps.simsmoke.outcome == 'success'"]:
                self.assertIn(term, condition)

    def test_cache_is_exact_simulator_xcode_project_source_provenance(self):
        item = step('Cache simulator Release DerivedData')
        self.assertIn('path: build/sim', item)
        self.assertIn('steps.simcache.outputs.key', item)
        self.assertNotIn('hashFiles', item)
        self.assertNotIn('restore-keys', item)
        self.assertIn('simulator-cache-key.py', script('Simulator Release cache provenance'))
        self.assertIn('xcodebuild -version', script('Simulator Release cache provenance'))
        self.assertIn('-derivedDataPath build/sim', script('Simulator Release build ('))
        self.assertIn('CFBundleVersion', script('Simulator Release build ('))

    def test_build_stamps_do_not_invalidate_cache_but_source_and_xcode_do(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('simkey', ROOT / 'scripts/release/simulator-cache-key.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            def git(*args):
                subprocess.run(['git', '-C', tmp, *args], check=True, capture_output=True)
            git('init')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'Test')
            (repo / 'Ate').mkdir()
            (repo / 'Ate/App.swift').write_text('source v1')
            (repo / 'project.yml').write_text('CURRENT_PROJECT_VERSION: 1')
            git('add', '.')
            git('commit', '-m', 'baseline')
            identity = lambda xcode: module.cache_identity(module.source_fingerprint(repo), xcode, 'Ate', 'false', 'macOS', 'ARM64')
            first = identity('Xcode 27.1 Build A')
            for build in (427, 428):
                (repo / 'project.yml').write_text(f'CURRENT_PROJECT_VERSION: {build}\nMARKETING_VERSION: 0.1.{build}\nATE_GIT_RUN_ID: {build}')
                (repo / 'Ate.xcodeproj').mkdir(exist_ok=True)
                (repo / 'Ate.xcodeproj/project.pbxproj').write_text(f'generated build {build}')
                self.assertEqual(identity('Xcode 27.1 Build A'), first)
            self.assertNotEqual(identity('Xcode 27.1 Build B'), first)
            (repo / 'Ate/App.swift').write_text('source v2')
            git('add', 'Ate/App.swift')
            git('commit', '-m', 'source change')
            self.assertNotEqual(identity('Xcode 27.1 Build A'), first)

    def test_full_log_timing_and_always_diagnostics(self):
        build = script('Simulator Release build (')
        self.assertIn('tee smoke/simulator-build.log', build)
        self.assertNotIn('tail -20', build)
        self.assertNotIn('-quiet', build)
        for name in ['Simulator Release build (', 'Release smoke test (A-CI-03) - install']:
            self.assertIn('trap finish_', script(name))
            self.assertIn('smoke/timing-summary.txt', script(name))
        for name in ['Collect simulator smoke diagnostics', 'Upload simulator smoke diagnostics']:
            self.assertIn('if: always()', step(name))
        self.assertIn('path: smoke/', step('Upload simulator smoke diagnostics'))
        self.assertIn('steps.simbuild.outcome', script('Report A-CI-03'))
        self.assertIn('steps.simsmoke.outcome', script('Report A-CI-03'))

    def run_mock(self, name, *, build_status=0, launch_status=0, screenshot_status=0, install_status=0, alive=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'bin').mkdir()
            (root / 'scripts').mkdir()
            (root / 'scripts/select-ios-simulator.py').write_text("print('test-simulator')\n")
            (root / 'build/sim/Build/Products/Release-iphonesimulator/Ate.app').mkdir(parents=True)
            commands = {
                'xcodebuild': f'echo full-build-log; exit {build_status}',
                'plutil': 'echo 427',
                'sleep': 'echo "sleep $*" >> calls',
                'xcrun': f'''echo "$*" >> calls
case "$*" in
  'simctl install '*) exit {install_status};;
  'simctl launch '*) echo "com.melusik.ate: $TEST_PID"; exit {launch_status};;
  *screenshot*) exit {screenshot_status};;
esac
exit 0''',
            }
            for command, body in commands.items():
                file = root / 'bin' / command
                file.write_text('#!/bin/bash\n' + body + '\n')
                file.chmod(0o755)
            env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], SCHEME='Ate', SENTRY_FATAL_PROOF='false', SENTRY_PROOF_SIM_ID='test-simulator', BUILD_NUMBER='427', GITHUB_ENV=str(root / 'env'), GITHUB_STEP_SUMMARY=str(root / 'summary'), TEST_PID=str(os.getpid()) if alive else '99999999')
            result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script(name)], cwd=root, env=env, capture_output=True, text=True)
            read = lambda file: (root / file).read_text() if (root / file).exists() else ''
            return result.returncode, read('calls'), read('smoke/simulator-build.log'), read('smoke/timing-summary.txt'), read('env')

    def test_failed_build_preserves_log_and_exit_code(self):
        code, calls, log, timing, env = self.run_mock('Simulator Release build (', build_status=42)
        self.assertEqual(code, 42)
        self.assertIn('full-build-log', log)
        self.assertIn('exit_code=42', timing)
        self.assertNotIn('simctl install', calls)
        self.assertNotIn('SMOKE_STATUS=pass', env)

    def test_failed_launch_cannot_reach_screenshot_or_pass(self):
        code, calls, _, timing, env = self.run_mock('Release smoke test (A-CI-03) - install', launch_status=17)
        self.assertEqual(code, 17)
        self.assertNotIn('screenshot', calls)
        self.assertNotIn('SMOKE_STATUS=pass', env)
        self.assertIn('exit_code=17', timing)

    def test_failed_install_cannot_launch_or_pass(self):
        code, calls, _, _, env = self.run_mock('Release smoke test (A-CI-03) - install', install_status=19)
        self.assertEqual(code, 19)
        self.assertNotIn('simctl launch', calls)
        self.assertNotIn('SMOKE_STATUS=pass', env)

    def test_dead_app_cannot_claim_pass(self):
        code, _, _, _, env = self.run_mock('Release smoke test (A-CI-03) - install', alive=False)
        self.assertNotEqual(code, 0)
        self.assertNotIn('SMOKE_STATUS=pass', env)
        self.assertIn('SMOKE_STATUS=fail', env)

    def test_screenshot_failure_cannot_claim_pass(self):
        code, calls, _, _, env = self.run_mock('Release smoke test (A-CI-03) - install', screenshot_status=23)
        self.assertEqual(code, 23)
        self.assertIn('sleep 10', calls)
        self.assertNotIn('SMOKE_STATUS=pass', env)

    def test_success_requires_install_launch_wait_screenshot_alive(self):
        code, calls, _, timing, env = self.run_mock('Release smoke test (A-CI-03) - install')
        self.assertEqual(code, 0)
        self.assertLess(calls.index('simctl install'), calls.index('simctl launch'))
        self.assertLess(calls.index('sleep 10'), calls.index('screenshot'))
        self.assertIn('kill -0 "$PID"', script('Release smoke test (A-CI-03) - install'))
        self.assertIn('SMOKE_STATUS=pass', env)
        self.assertIn('exit_code=0', timing)
