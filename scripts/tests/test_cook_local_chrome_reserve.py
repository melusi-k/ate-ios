"""Pushed Cook reserves the actual inset owner's height, not stale root Y."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class CookLocalChromeReserveTests(unittest.TestCase):
    def test_owner_measures_and_injects_live_height_before_navigation(self):
        source = (ROOT / 'Ate/App/AteApp.swift').read_text()
        inset = source.split('struct TimerBarInset:', 1)[1].split('extension View { func withTimerBar', 1)[0]
        self.assertIn('@State private var measuredChromeHeight: CGFloat = 0', inset)
        self.assertIn('content.environment(\\.pushedCookChromeHeight, showsPushedChrome ? measuredChromeHeight : 0)', inset)
        self.assertIn('.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredChromeHeight = $0 }', inset)
        self.assertIn('CookSessionMiniPlayer(session: session)', inset)
        self.assertIn('TimerBar()', inset)
    def test_cook_reserve_is_height_based_and_strict_geometry_test_survives(self):
        source = (ROOT / 'Ate/Views/CookModeView.swift').read_text()
        self.assertIn('return pushedCookChromeHeight + 8', source)
        self.assertIn('guard store.cookTarget == nil, !store.isAtTabRoot,', source)
        self.assertNotIn('CookHostBottomYKey', source)
        self.assertNotIn('hostBottomY - bottomChromeMinY', source)
        test = (ROOT / 'AteUITests/CookFinishAccessoryUITests.swift').read_text()
        self.assertIn('finish.exists && finish.isHittable && finish.frame.height > 0 && finish.frame.maxY <= mini.frame.minY', test)
        self.assertIn('timeout: 10)', test)
        self.assertIn('XCTAssertEqual(result, .completed)', test)
        self.assertIn('cookCompletion.recorded', test)
