from approved_merge_534 import normalize
from pathlib import Path
import unittest
from settings_about_receipt_contract import original_coverage_bytes
ROOT=Path(__file__).resolve().parents[2]
class SettingsAboutReceiptTests(unittest.TestCase):
    def test_exact_reversal_retains_every_original_assertion_swipe_and_allowance(self):
        original_coverage_bytes(normalize('source:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_bytes()))
    def test_default_on_debug_receipts_are_two_checks_without_actions(self):
        helper=(ROOT/'AteUITests/SettingsAboutGeometryReceipt.swift').read_text()
        self.assertTrue(helper.startswith('#if DEBUG'))
        for text in ['phase < 2','phase > 0 || !visible','first-failed-check','after-scroll-check','row=','window=','nav=','tab=','accessory=','.keepAlways']:
            self.assertIn(text,helper)
        for text in ['.tap(','.swipe','sleep(', 'waitFor','ProcessInfo','UserDefaults']:
            self.assertNotIn(text,helper)
