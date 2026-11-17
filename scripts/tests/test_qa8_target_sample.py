import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest import mock
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('capture',ROOT/'scripts/capture-qa8-target-sample.py')
capture=importlib.util.module_from_spec(spec);spec.loader.exec_module(capture)

class TargetSampleTests(unittest.TestCase):
    def test_busy_target(self):
        self.assertEqual(capture.target('pid=62824 phase=exit-return uptime=2112.906','pid=62824 phase=scheduler-fired uptime=2118.008 phaseElapsed=5.103'),62824)
    def test_healthy_main_no_sample(self):
        self.assertIsNone(capture.target('pid=62824 phase=exit-return uptime=2112.906\npid=62824 phase=main-heartbeat uptime=2118.007','pid=62824 phase=scheduler-fired uptime=2118.008 phaseElapsed=5.103'))
    def test_missing_mixed_or_premature_evidence(self):
        main='pid=62824 phase=exit-return uptime=2112.906'
        for sched in ['', 'pid=62825 phase=scheduler-fired uptime=2118.008 phaseElapsed=5.103','pid=62824 phase=scheduler-fired uptime=2113 phaseElapsed=0.1']:
            self.assertIsNone(capture.target(main,sched))
        self.assertIsNone(capture.target('pid=62824 phase=exit-enter uptime=2112.906','pid=62824 phase=scheduler-fired uptime=2118.008 phaseElapsed=5.103'))
    def test_identity_strict_one_simulator_executable(self):
        self.assertTrue(capture.identity_matches('/Users/runner/Library/Developer/CoreSimulator/Devices/SIM-123/data/Containers/Bundle/Application/XYZ/Ate.app/Ate\n','SIM-123'))
        for name in ['/Applications/Ate.app/Ate','/SIM-123/AteUITests-Runner.app/Runner','/SIM-123/Ate.app/Ate other','Ate.app/Ate']:
            self.assertFalse(capture.identity_matches(name,'SIM-123'))
    def test_no_scope_or_budget_expansion(self):
        script=(ROOT/'scripts/capture-qa8-target-sample.py').read_text()
        workflow=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        self.assertIn("['/usr/bin/sample',str(pid),'3','10','-file'",script)
        self.assertIn('CHILD.wait(timeout=15)',script)
        self.assertIn('signal.signal(signal.SIGTERM,stop)',script)
        self.assertNotIn("['sudo'",script)
        self.assertIn('stop_qa8_sample\' EXIT',workflow)
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',workflow)
        self.assertIn('            qa8-target-sample\n',workflow)


def restore_target_capture(test, text):
    block='          mkdir -p qa8-target-sample\n          python3 scripts/capture-qa8-target-sample.py --sim-id "$SIM_ID" --output qa8-target-sample > qa8-target-sample/collector-console.txt 2>&1 &\n          qa8_sample_pid=$!\n          stop_qa8_sample() {\n            kill "$qa8_sample_pid" 2>/dev/null || true\n            wait "$qa8_sample_pid" || true\n          }\n'
    test.assertEqual(text.count(block),1)
    text=text.replace(block,'',1)
    before='; stop_qa8_sample\' EXIT'
    test.assertEqual(text.count(before),1)
    text=text.replace(before,"' EXIT",1)
    artifact='            qa8-target-sample\n'
    test.assertEqual(text.count(artifact),1)
    return text.replace(artifact,'',1)

class CaptureExecutionTests(unittest.TestCase):
    def fixture(self, folder):
        container=Path(folder)/'SIM-123'/'data'
        cache=container/'Library'/'Caches';cache.mkdir(parents=True)
        (cache/'qa8-exit-diagnostic.txt').write_text('pid=62824 phase=exit-return uptime=2112.906')
        (cache/'qa8-exit-scheduler.txt').write_text('pid=62824 phase=scheduler-fired uptime=2118.008 phaseElapsed=5.103')
        return container
    def test_one_bounded_targeted_capture_and_return(self):
        with tempfile.TemporaryDirectory() as d:
            container=self.fixture(d);output=Path(d)/'out'
            with mock.patch.object(capture.time,'time',return_value=100), mock.patch.object(capture.time,'monotonic',return_value=0), mock.patch.object(capture.subprocess,'run',side_effect=[SimpleNamespace(returncode=0,stdout=str(container)),SimpleNamespace(returncode=0,stdout='/Users/runner/SIM-123/data/Bundle/Ate.app/Ate\n')]) as read, mock.patch.object(capture.subprocess,'Popen') as popen:
                popen.return_value.wait.return_value=0
                capture.capture('SIM-123',output)
                self.assertEqual(read.call_count,2)
                self.assertEqual(popen.call_count,1)
                self.assertEqual(popen.call_args.args[0],['/usr/bin/sample','62824','3','10','-file',str(output/'qa8-ate-only.sample.txt')])
                popen.return_value.wait.assert_called_once_with(timeout=15)
                self.assertIn('sample-returncode=0',(output/'status.txt').read_text())
    def test_identity_failure_no_capture_no_retry(self):
        with tempfile.TemporaryDirectory() as d:
            container=self.fixture(d);output=Path(d)/'out'
            with mock.patch.object(capture.time,'time',return_value=100), mock.patch.object(capture.time,'monotonic',return_value=0), mock.patch.object(capture.subprocess,'run',side_effect=[SimpleNamespace(returncode=0,stdout=str(container)),SimpleNamespace(returncode=0,stdout='/Applications/Ate.app/Ate\n')]), mock.patch.object(capture.subprocess,'Popen') as popen:
                capture.capture('SIM-123',output)
                popen.assert_not_called()
                self.assertIn('identity-unverified',(output/'status.txt').read_text())
    def test_stale_evidence_never_used(self):
        with tempfile.TemporaryDirectory() as d:
            container=self.fixture(d);output=Path(d)/'out'
            with mock.patch.object(capture.time,'time',return_value=9999999999), mock.patch.object(capture.time,'monotonic',side_effect=[0,0,1801]),mock.patch.object(capture.time,'sleep'), mock.patch.object(capture.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=str(container))) as read, mock.patch.object(capture.subprocess,'Popen') as popen:
                capture.capture('SIM-123',output)
                popen.assert_not_called();self.assertEqual(read.call_count,1)
                self.assertIn('watch-expired',(output/'status.txt').read_text())
    def test_collector_timeout_kills_and_does_not_retry(self):
        with tempfile.TemporaryDirectory() as d:
            container=self.fixture(d);output=Path(d)/'out'
            with mock.patch.object(capture.time,'time',return_value=100), mock.patch.object(capture.time,'monotonic',return_value=0), mock.patch.object(capture.subprocess,'run',side_effect=[SimpleNamespace(returncode=0,stdout=str(container)),SimpleNamespace(returncode=0,stdout='/Users/runner/SIM-123/data/Bundle/Ate.app/Ate\n')]), mock.patch.object(capture.subprocess,'Popen') as popen:
                popen.return_value.wait.side_effect=[capture.subprocess.TimeoutExpired('sample',15),-9]
                capture.capture('SIM-123',output)
                self.assertEqual(popen.call_count,1);popen.return_value.kill.assert_called_once()
                self.assertIn('sample-collector-timeout=15',(output/'status.txt').read_text())
    def test_stop_terminates_child(self):
        child=mock.Mock();child.poll.return_value=None
        with mock.patch.object(capture,'CHILD',child):
            with self.assertRaises(SystemExit):capture.stop()
            child.terminate.assert_called_once();child.wait.assert_called_once_with(timeout=2)
