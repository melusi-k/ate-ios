from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

# Geometry-model preflight, not execution of XCTest gestures or native pixels.
def drag(top, bottom, row_top, row_height):
    middle = (top + bottom) / 2
    row_middle = row_top + row_height / 2
    if row_height > bottom - top:
        return 0
    if row_top < top:
        return min((bottom - top) * .6, middle - row_middle)
    if row_top + row_height > bottom:
        return max(-(bottom - top) * .6, middle - row_middle)
    return 0

class IngredientScrollGeometry(unittest.TestCase):
    def test_above_below_and_footer_overlap_use_correct_direction(self):
        self.assertGreater(drag(180, 700, 100, 30), 0)
        self.assertLess(drag(180, 700, 900, 30), 0)
        self.assertLess(drag(180, 700, 690, 30), 0)
        self.assertEqual(drag(180, 700, 200, 30), 0)
        self.assertEqual(drag(180, 700, 200, 600), 0)

    def test_model_converges_and_stops_without_passing_short_row(self):
        for initial in [-900, 100, 179, 400, 690, 1000, 1600]:
            row = initial
            for _ in range(5):
                delta = drag(180, 700, row, 30)
                self.assertLessEqual(abs(delta), 520 * .6)
                if delta == 0:
                    break
                row += delta
            self.assertGreaterEqual(row, 180)
            self.assertLessEqual(row + 30, 700)
            self.assertEqual(drag(180, 700, row, 30), 0)

    def test_original_geometry_assertions_capture_and_five_gesture_budget(self):
        helper = (ROOT / 'AteUITests/RecipeDetailVisibility.swift').read_text()
        self.assertIn('for attempt in 0..<5', helper)
        self.assertIn('if contains(row, scroll: scroll, header: header, footer: footer) { return }', helper)
        self.assertIn('if frame.minY < band.minY', helper)
        self.assertIn('else if frame.maxY > band.maxY', helper)
        self.assertIn('withVelocity: .slow, thenHoldForDuration: 0.1', helper)
        self.assertIn('band.contains(frame) && row.isHittable', helper)
        self.assertNotIn('.swipeUp()', helper)
        for file, row, capture in [('CoverageUITests.swift', 'firstIngredient', 'shot("recipe-sheet-full-first-ingredient-clear-of-cook-normal")'),
                                   ('IngredientDisplayUITests.swift', 'row', 'retain("recipe-detail-identical-lemon-row-once-normal")')]:
            source = (ROOT / 'AteUITests' / file).read_text()
            reveal = source.index('RecipeDetailVisibility.reveal(' + row)
            shot = source.index(capture, reveal)
            assertion = source.index('XCTAssertTrue(RecipeDetailVisibility.contains(' + row, reveal)
            self.assertLess(reveal, shot)
            self.assertLess(shot, assertion)
