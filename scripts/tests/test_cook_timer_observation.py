"""Source ownership checks, not native redraw/performance qualification."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class CookTimerObservationTests(unittest.TestCase):
    def test_full_cook_does_not_read_clock(self):
        source = (ROOT / 'Ate/Views/CookModeView.swift').read_text()
        cook = source.split('struct CookTimerCountdown:', 1)[0]
        self.assertNotIn('timers.now', cook)
        self.assertNotIn('clock.now', cook)
        self.assertIn('CookTimerCountdown(timer: active, fallback: secs, clock: store.timers)', cook)
        self.assertIn('CookOtherTimerButton(timer: t, clock: store.timers)', cook)

    def test_leaf_preserves_visible_and_spoken_countdown(self):
        source = (ROOT / 'Ate/Views/CookModeView.swift').read_text()
        countdown = source.split('struct CookTimerCountdown:', 1)[1].split('struct CookOtherTimerButton:', 1)[0]
        self.assertIn('timer?.remaining(at: clock.now) ?? fallback', countdown)
        self.assertIn('.accessibilityIdentifier("cookTimerValue")', countdown)
        self.assertIn('.accessibilityAddTraits(.updatesFrequently)', countdown)
        self.assertIn('CookModeView.spoken(remaining)', countdown)
        self.assertIn('timer?.isRunning == true', countdown)

    def test_static_recipe_rows_are_semantic_not_hidden_or_lazy(self):
        source = (ROOT / 'Ate/Views/Components.swift').read_text().split('struct RecipeCardView:', 1)[1].split('/// Simple wrapping row', 1)[0]
        self.assertEqual(source.count('.accessibilityElement(children: .combine)'), 2)
        self.assertIn('.accessibilityIdentifier("recipe.steps.heading")', source)
        self.assertIn('.accessibilityIdentifier("recipe.ingredient.', source)
        self.assertIn('.accessibilityIdentifier("recipe.step.', source)
        self.assertNotIn('accessibilityHidden', source)
        self.assertNotIn('LazyVStack', source)
