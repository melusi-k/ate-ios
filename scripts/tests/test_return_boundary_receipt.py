from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class ReturnBoundaryReceiptTests(unittest.TestCase):
    def test_exact_original_predicate_and_waiter_assertion_preserved(self):
        s=(ROOT/'AteUITests/CookFinishAccessoryUITests.swift').read_text()
        for addition in ['        #if DEBUG\n        if !landscape { ReturnBoundaryReceipt.capture(app, phase: "cook-portrait-before-clear-query") }\n        #endif\n', '        #if DEBUG\n        if !landscape { ReturnBoundaryReceipt.capture(app, phase: "cook-portrait-after-clear-query") }\n        #endif\n']:
            self.assertEqual(s.count(addition),1)
            s=s.replace(addition,'')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'65fc8dc2d2a576c8acfad843e7ebf53d224a3d72e9f164a29a55449bccc8875c')
    def test_debug_only_capture_has_no_actions_or_waits(self):
        h=(ROOT/'AteUITests/ReturnBoundaryReceipt.swift').read_text()
        self.assertTrue(h.startswith('#if DEBUG'))
        self.assertIn('app.screenshot()',h)
        self.assertIn('app.debugDescription',h)
        for term in ['.tap(','.swipe','waitFor','sleep(','UserDefaults','ProcessInfo']:
            self.assertNotIn(term,h)
