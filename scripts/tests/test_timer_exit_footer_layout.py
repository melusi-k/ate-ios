"""Source preflight only: unchanged native QA8 owns timer-exit acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class TimerExitFooterLayoutContracts(unittest.TestCase):
    def test_actual_scroll_owns_transparent_floating_cook_once_and_keeps_measured_reserve(self):
        source = (ROOT / 'Ate/Views/RecipeDetailView.swift').read_text()
        scroll = source.split('.accessibilityIdentifier("recipe.detail.scroll")', 1)[1].split('RecipeNotFoundView', 1)[0]
        self.assertIn('.overlay(alignment: .bottom)', scroll)
        self.assertIn('.padding(.bottom, footerChromeReserve)', scroll)
        self.assertNotIn('.background(', scroll)
        self.assertNotIn('.safeAreaInset(edge: .bottom', source)
        self.assertIn('.padding(.bottom, editing ? 16 : 16 + 72 + footerChromeReserve)', source)
        self.assertIn('.primary, height: 56', scroll)
        self.assertIn('.padding(.vertical, 8)', scroll)
        self.assertEqual(source.count('.overlay(alignment: .bottom)'), 1)
        self.assertIn('max(0, hostBottomY - bottomChromeMinY) + 8', source)
        self.assertIn('store.beginCookSession(recipeID: recipeID, factor: factor)', scroll)
        self.assertIn('store.cookTarget = CookTarget(id: recipeID)', scroll)

    def test_qa8_still_requires_transient_bar_actual_completion_and_resume(self):
        source = (ROOT / 'AteUITests/KeyFlowsQATests.swift').read_text()
        test = source.split('func testQA8_Timers()',1)[1].split('// MARK: Legal',1)[0]
        for phrase in ['launch(["-qaFastTimers"])', 'addPrompt("Timer test salmon")',
                       'wait(app.buttons["timerBarOpen"].firstMatch, 5)',
                       'waitForNonExistence(timeout: 40)', 'probe.label.contains("chime=1")',
                       'probe.label.contains("haptic=1")', 'paused timer doesn\'t move',
                       'miniPlayer.tap()', 'explicit completion clears the cooking session']:
            self.assertIn(phrase, test)
