"""Source-only audit regression. Native pixels/AX remain UNRUN."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AuditSlice(unittest.TestCase):
    def test_authorized_source_change(self):
        s=(ROOT/'Ate/Views/CookModeView.swift').read_text()
        action=s.split('.alert("Could not save this cook"',1)[1].split('if finishProblem ==',1)[0]
        self.assertIn('Button("Dismiss", role: .cancel) { finishProblem = nil }',action)
        self.assertNotIn('Button("Try again"',action)
        self.assertNotIn('finish(recipe)',action)
        self.assertNotIn('store.',action)
        self.assertNotIn('completionOutbox.',action)
    def test_additive_inverse_is_exact_and_fails_closed(self):
        from audit_cook_retry_delta import restore,PATH,BASE
        import hashlib
        raw=(ROOT/PATH).read_text()
        self.assertEqual(hashlib.sha256(restore(PATH,raw).encode()).hexdigest(),BASE)
        for changed in [raw+'// mutation',raw.replace('Dismiss','Try again',1) if 'Dismiss' in raw else raw+' ']:
            with self.assertRaises(AssertionError):restore(PATH,changed)
