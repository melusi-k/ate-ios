"""Diagnostics cannot repair or weaken the real off-Main contract."""
from pathlib import Path
import hashlib, re, unittest
ROOT = Path(__file__).resolve().parents[2]
class CookRemovalPhaseDiagnosticTests(unittest.TestCase):
    def test_exact_native_inverse_preserves_all_assertions_and_caps(self):
        source = (ROOT/'AteTests/CookPlanNotificationTests.swift').read_text()
        diagnostic = source.split('// Diagnostic output only: monotonic correlation, no scheduling or synchronization.')[1]
        original = source.split('// Diagnostic output only: monotonic correlation, no scheduling or synchronization.')[0]
        original = re.sub(r'^ +cookRemovalDiagnostic\("[a-z-]+"\)\n', '', original, flags=re.M).rstrip()+'\n'
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(), '73ebbb792a5a6c773c9fc5f1483457f5396edfcacca97625bebbbce4c3c2f22a')
        self.assertIn('DispatchTime.now().uptimeNanoseconds',diagnostic)
        self.assertIn('Thread.isMainThread',diagnostic)
        self.assertNotIn('Task {',diagnostic)
        self.assertNotIn('DispatchQueue',diagnostic)
        self.assertEqual(source.count('cookRemovalDiagnostic("'),11)
        from cookplan_cancel_phase_delta import restore as restore_cancel_phases
        self.assertEqual(hashlib.sha256(restore_cancel_phases('Ate/Services/CookPlanNotifications.swift',(ROOT/'Ate/Services/CookPlanNotifications.swift').read_bytes())).hexdigest(),'4948a4701ea465790e97d29a357d76e08d9031c25ca865aa051809aa1e1c2c55')
