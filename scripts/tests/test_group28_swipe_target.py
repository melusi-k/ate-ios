from pathlib import Path
import unittest
from group28_swipe_target_delta import restore,OLD,NEW
ROOT=Path(__file__).resolve().parents[2]
class Group28SwipeTarget(unittest.TestCase):
    def test_only_single_gesture_target_changes_and_original_assertions_remain(self):
        source=(ROOT/'AteUITests/AteUITests.swift').read_text()
        section=source.split('func test28_GroupSortAndMenus()',1)[1].split('    func test29_',1)[0]
        self.assertEqual(section.count('.swipeRight()'),1)
        for token in ['appleRow.count, 1','appleRow.element(boundBy: 0).swipeRight()',
                      'wait(app.buttons["Favourite"].firstMatch, 3)',
                      'app.buttons["Favourite"].firstMatch.tap()',
                      'wait(text("Added to Favourites"), 3)']:
            self.assertIn(token,section)
        self.assertNotIn('a.swipeRight()',section)
        parent=restore('AteUITests/AteUITests.swift',source)
        self.assertIn(OLD,parent)
        self.assertNotIn(NEW,parent)
        for mutant in [source.replace(NEW,'',1), source+NEW]:
            with self.assertRaises(AssertionError):restore('AteUITests/AteUITests.swift',mutant)
