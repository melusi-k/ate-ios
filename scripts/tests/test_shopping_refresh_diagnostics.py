from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ShoppingRefreshDiagnosticTests(unittest.TestCase):
    def test_original_ready_and_success_predicates_and_ten_second_limits_remain(self):
        ui = (ROOT / 'AteUITests/ShoppingSyncCaptureUITests.swift').read_text()
        self.assertIn('exists == true AND enabled == true AND hittable == true', ui)
        self.assertIn('label BEGINSWITH %@', ui)
        self.assertIn('predicate: ready, object: refresh)], timeout: 10)', ui)
        self.assertIn('predicate: synced, object: status)], timeout: 10)', ui)
        self.assertIn('XCTAssertEqual(readyResult, .completed)', ui)
        self.assertIn('XCTAssertEqual(syncedResult, .completed)', ui)
        for forbidden in ['executionTimeAllowance', 'continueAfterFailure = true', 'sleep(', 'refresh.tap(); refresh.tap()']:
            self.assertNotIn(forbidden, ui)

    def test_failure_pixels_precede_potentially_stalled_ax_queries(self):
        ui = (ROOT / 'AteUITests/ShoppingSyncCaptureUITests.swift').read_text()
        helper = ui.split('private func refreshDiagnostics', 1)[1].split('private func shopping()', 1)[0]
        self.assertLess(helper.index('XCUIScreen.main.screenshot()'), helper.index('record("refresh.exists")'))
        for field in ['refresh.exists', 'refresh.isEnabled', 'refresh.isHittable', 'refresh.frame',
                      'status.label', 'sidebar.frame', 'sidebarToggle.frame', 'app.debugDescription']:
            self.assertIn(field, helper)
        self.assertIn('post-ready-failure', ui)
        self.assertIn('post-sync-failure', ui)
        self.assertIn('shopping-immediately-post-refresh-tap-', ui)
        self.assertIn('SNAPSHOT-CHUNK', helper)
