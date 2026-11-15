from approved_merge_537 import normalize
from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[2]
class ReturnServingsFullTests(unittest.TestCase):
    def test_entire_ui_reconstructs_exact_117(self):
        s=normalize('source:AteUITests/CoverageUITests.swift', (ROOT/'AteUITests/CoverageUITests.swift').read_text())
        replacement='        // Medium detent prioritizes native sheet resizing over downward content\n        // scrolling. Expand once before returning through the retained detail.\n        shot("recipe-sheet-reexpanded-medium-before-return-to-servings")\n        fully.tap()\n        RecipeDetailVisibility.reveal(servings, scroll: detailScroll, header: header, footer: cookFooter)\n        shot("recipe-sheet-reexpanded-full-after-return-to-servings")'
        self.assertEqual(s.count(replacement),1)
        self.assertEqual(replacement.count('fully.tap()'),1)
        self.assertEqual(hashlib.sha256(s.replace(replacement,'        for _ in 0..<5 where !servings.isHittable { detailScroll.swipeDown() }').encode()).hexdigest(),'e2e8cd233a8817679055488d43ce7f4d097d760e329a2289ee43dbaa5356e7a6')
        helper=normalize('source:AteUITests/RecipeDetailVisibility.swift', (ROOT/'AteUITests/RecipeDetailVisibility.swift').read_text())
        self.assertIn('for attempt in 0..<5',helper)
