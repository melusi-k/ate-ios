from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class TimerExitFooterLayout(unittest.TestCase):
    def test_actual_scroll_owns_opaque_cook_inset_and_preserves_reserve(self):
        s=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        scroll=s.split('.accessibilityIdentifier("recipe.detail.scroll")',1)[1].split('RecipeNotFoundView',1)[0]
        for phrase in ['.safeAreaInset(edge: .bottom', '.padding(.bottom, footerChromeReserve)', '.background(Theme.background.ignoresSafeArea(edges: .bottom))', 'store.beginCookSession(recipeID: recipeID, factor: factor)']:
            self.assertIn(phrase,scroll)
        self.assertEqual(s.count('.safeAreaInset(edge: .bottom'),1)
