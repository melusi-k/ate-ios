from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
NEW='        let afterSwipe = weeklyCard.frame\n        if !(afterSwipe.minX < before.minX) {\n            // Freeze the failed comparison before collecting diagnostics. Never\n            // swipe again or remeasure movement to turn the failure into a pass.\n            let failure = XCTAttachment(screenshot: XCUIScreen.main.screenshot())\n            failure.name = "insights-horizontal-swipe-no-movement"; failure.lifetime = .keepAlways; add(failure)\n            print("INSIGHTS-SWIPE-NO-MOVEMENT before=\\(before) after=\\(afterSwipe)")\n            print("INSIGHTS-SWIPE-DIAGNOSTIC geometry begin")\n            print("INSIGHTS-SWIPE-DIAGNOSTIC carousel=\\(carousel.frame) window=\\(app.windows.firstMatch.frame)")\n            print("INSIGHTS-SWIPE-DIAGNOSTIC geometry end")\n        }\n        XCTAssertLessThan(afterSwipe.minX, before.minX, "Horizontal swipe must move the card lane")\n'
OLD='        XCTAssertLessThan(weeklyCard.frame.minX, before.minX, "Horizontal swipe must move the card lane")\n'
class SwipeFailureDiagnostic546(unittest.TestCase):
    def test_entire_original_ui_reconstructs_and_mutants_fail(self):
        def restore(raw):
            assert raw.count(NEW)==1
            raw=raw.replace(NEW,OLD,1)
            assert hashlib.sha256(raw.encode()).hexdigest()=='fbb3665624537cc7bbb6ef8bb83e8308985ca161dac3bb9c82310e3d03ac2916'
        raw=(ROOT/'AteUITests/InsightsAcceptanceUITests.swift').read_text();restore(raw)
        for changed in [raw.replace(NEW,'',1),raw+NEW,raw.replace('XCTAssertLessThan(afterSwipe.minX','XCTAssertGreaterThan(afterSwipe.minX',1)]:
            with self.assertRaises(AssertionError):restore(changed)
    def test_failure_value_frozen_and_pixels_before_extra_ax_reads(self):
        self.assertLess(NEW.index('let afterSwipe = weeklyCard.frame'),NEW.index('if !(afterSwipe.minX < before.minX)'))
        self.assertLess(NEW.index('XCUIScreen.main.screenshot()'),NEW.index('carousel.frame'))
        self.assertEqual(NEW.count('weeklyCard.frame'),1)
        self.assertIn('XCTAssertLessThan(afterSwipe.minX, before.minX',NEW)
        for token in ['.swipe', '.tap(', 'waitFor', 'sleep(', 'timeout:', 'while ']:self.assertNotIn(token,NEW)
    def test_search_single_input_predicates_and_budgets_byte_unchanged(self):
        self.assertEqual(hashlib.sha256((ROOT/'AteUITests/ExploreUITests.swift').read_bytes()).hexdigest(),'5e300bda3a3f8ab02caae977a6d3906f0d1df4700b11d29cbbb443af6fcf1b25')
