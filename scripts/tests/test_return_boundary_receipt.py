from approved_merge_539 import normalize
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class ReturnBoundaryReceiptTests(unittest.TestCase):
    def test_exact_original_journey_preserved(self):
        s=normalize('receipt:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_text())
        for addition in ['        #if DEBUG\n        ReturnBoundaryReceipt.capture(app, phase: "landscape-grid-close-before-query")\n        #endif\n', '        #if DEBUG\n        ReturnBoundaryReceipt.capture(app, phase: "landscape-grid-close-after-query")\n        #endif\n']:
            self.assertEqual(s.count(addition),1)
            s=s.replace(addition,'')
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'69a7cb7caefc2ba02cd154174f58c61494bd87777be6e066157e793ca334d91c')
    def test_only_two_default_debug_receipts_no_extra_actions_waits(self):
        helper=normalize('receipt:AteUITests/ReturnBoundaryReceipt.swift', (ROOT/'AteUITests/ReturnBoundaryReceipt.swift').read_text())
        self.assertTrue(helper.startswith('#if DEBUG'))
        for term in ['app.screenshot()','app.debugDescription','.keepAlways']:
            self.assertIn(term,helper)
        for term in ['.tap(','.swipe','waitFor','sleep(','ProcessInfo','UserDefaults']:
            self.assertNotIn(term,helper)

def restore_return_boundary(test,text):
    for addition in ['        #if DEBUG\n        ReturnBoundaryReceipt.capture(app, phase: "landscape-grid-close-before-query")\n        #endif\n', '        #if DEBUG\n        ReturnBoundaryReceipt.capture(app, phase: "landscape-grid-close-after-query")\n        #endif\n']:
        test.assertEqual(text.count(addition),1)
        text=text.replace(addition,'')
    test.assertEqual(hashlib.sha256(text.encode()).hexdigest(),'69a7cb7caefc2ba02cd154174f58c61494bd87777be6e066157e793ca334d91c')
    return text
