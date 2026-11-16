import importlib.util,unittest,tempfile,hashlib
from pathlib import Path
from unittest.mock import patch
from tracker_query_sample_delta import restore,BASE
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('tracker_sample',ROOT/'scripts/sample-tracker-query.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class TrackerQuerySample(unittest.TestCase):
    def test_exact_workflow_inverse_rejects_mutations(self):
        s=(ROOT/'.github/workflows/compile-check.yml').read_text()
        self.assertEqual(hashlib.sha256(restore('source:.github/workflows/compile-check.yml',s).encode()).hexdigest(),BASE)
        for changed in [s+'# mutation',s.replace('120 -maximum-test','121 -maximum-test',1)]:
            with self.assertRaises(AssertionError):restore('source:.github/workflows/compile-check.yml',changed)
    def test_one_capture_only_when_first_query_stays_blocked(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);log=root/'log';stop=root/'stop'
            log.write_text(m.TEST+"]' started.\n"+m.QUERY+'month\n    t = 59 Find the "tracker.displayedMonth" StaticText\n')
            with patch.object(m,'capture') as cap,patch.object(m.time,'monotonic',side_effect=[0,0,0,6,6]),patch.object(m.time,'sleep'):
                m.monitor(log,root/'out','SIM',stop);cap.assert_called_once_with(root/'out','SIM')
            log.write_text(log.read_text()+'    t = 60 Find the "tracker.nextMonth" Button\n')
            with patch.object(m,'capture') as cap:
                m.monitor(log,root/'out','SIM',stop);cap.assert_not_called()
    def test_capture_is_scoped_and_bounded(self):
        with tempfile.TemporaryDirectory() as d:
            class R:
                stdout='123 0 UIKitApplication:com.melusik.ate[abc]\n124 0 com.apple.accessibilityd\n125 0 unrelated\n'
                stderr='';returncode=0
            with patch.object(m.subprocess,'run',return_value=R()) as run:
                m.capture(Path(d),'SIM')
                self.assertEqual(run.call_count,3)
                self.assertEqual(run.call_args_list[0].args[0],['xcrun','simctl','spawn','SIM','launchctl','list'])
                self.assertTrue(all(c.kwargs['timeout']<=8 for c in run.call_args_list))
