from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SettingsToolsLazyRevealTests(unittest.TestCase):
    def test_every_tools_row_gets_own_scroll_before_original_wait_and_hittability(self):
        ui = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        test = ui.split('func test32_MoreCollectionsToolsAbout()', 1)[1].split('shot("settings-tools")', 1)[0]
        self.assertIn('for identifier in ["settings.export", "settings.import", "settings.replayOnboarding"]', test)
        self.assertLess(test.index('scrollTo(control)'), test.index('wait(control, 3)'))
        self.assertIn('XCTAssertTrue(control.isHittable', test)
        self.assertLess(test.index('shot("settings-tools-unreachable-"'), test.index('wait(control, 3)'))
        self.assertIn('app.debugDescription', test)
        self.assertIn('print(hierarchy)', test)
        # No scroll-budget/timeout change, extra retry, or existence-only shortcut.
        helper = ui.split('func scrollTo(', 1)[1].split('func tab(', 1)[0]
        self.assertIn('max: Int = 25', helper)
        self.assertIn('waitForExistence(timeout: 2)', helper)
        self.assertNotIn('continueAfterFailure = true', test)
        self.assertNotIn('sleep(', test)
