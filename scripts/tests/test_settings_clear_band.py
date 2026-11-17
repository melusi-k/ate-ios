from approved_merge_539 import normalize
"""One gesture setup only. Native Settings pixels/AX still own acceptance."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SettingsClearBandTests(unittest.TestCase):
    def test_entire_ui_file_reconstructs_exact_d994_original(self):
        source = normalize('main:AteUITests/CoverageUITests.swift', (ROOT / 'AteUITests/CoverageUITests.swift').read_text())
        replacement = '        // A default swipeDown travels only 200pt on the retained runtime. Use\n        // one held drag across the real clear Form band, not another gesture.\n        let formFrame = settingsForm.frame\n        let navigationFrame = settingsTitle.frame\n        let tabFrame = app.tabBars.firstMatch.frame\n        let clearTop = max(formFrame.minY, navigationFrame.maxY) + 8\n        let clearBottom = min(formFrame.maxY, tabFrame.minY) - 8\n        XCTAssertGreaterThan(clearBottom, clearTop, "Settings must expose a clear Form band")\n        let formOrigin = settingsForm.coordinate(withNormalizedOffset: .zero)\n        let dragStart = formOrigin.withOffset(CGVector(dx: formFrame.width / 2,\n                                                       dy: clearTop - formFrame.minY))\n        let dragEnd = formOrigin.withOffset(CGVector(dx: formFrame.width / 2,\n                                                     dy: clearBottom - formFrame.minY))\n        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd, withVelocity: .slow, thenHoldForDuration: 0.1)'
        self.assertEqual(source.count(replacement), 1)
        restored = source.replace(replacement, '        settingsForm.swipeDown()')
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), 'b95619343145b3798921397816ec1798a7d0a2b2125f15c4a979ec4f21473c58')
        self.assertEqual(replacement.count('thenDragTo:'), 1)
        self.assertNotIn('for ', replacement)
        self.assertNotIn('while ', replacement)
