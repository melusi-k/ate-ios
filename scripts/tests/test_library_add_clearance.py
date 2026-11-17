from pathlib import Path
import hashlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class LibraryAddClearanceContracts(unittest.TestCase):
    def test_list_and_grid_share_measured_content_reserve(self):
        source = (ROOT/'Ate/Views/LibraryView.swift').read_text()
        self.assertIn('@Environment(\\.bottomChromeMinY)', source)
        self.assertIn('geometry.frame(in: .global).maxY', source)
        self.assertIn('.onPreferenceChange(LibraryScrollBottomKey.self)', source)
        self.assertEqual(source.count('Color.clear.frame(height: bottomContentClearance).accessibilityHidden(true)'), 2)
        # Measurement is on the viewport container before sheets, never on content including its own reserve.
        host = source.split('var body: some View {', 1)[1].split('// Attach the recipe quick-look sheet', 1)[0]
        self.assertIn('if useGrid { grid(filtered) } else { list(filtered) }', host)
        self.assertIn('.background(GeometryReader', host)
        self.assertNotIn('Color.clear.frame(height: 96)', source)
    def test_reserve_uses_actual_overlap_with_safe_pre_measurement_fallback(self):
        source = (ROOT/'Ate/Logic/LibraryChromeClearance.swift').read_text()
        self.assertIn('hostBottom.isFinite, chromeTop.isFinite', source)
        self.assertIn('max(0, hostBottom - chromeTop) + 16', source)
        self.assertIn('else { return 96 }', source)
    def test_native_journey_asserts_actual_geometry_and_tap_without_injection(self):
        source = (ROOT/'AteUITests/LibraryAddClearanceUITests.swift').read_text()
        for token in ['last.frame.maxY, add.frame.minY', 'last.tap()', 'promptEditor', 'accessoryAdd',
                      'last.isHittable', 'add.isHittable', 'window.width', 'window.height', '.landscapeLeft', '.portrait']:
            self.assertIn(token, source)
        for token in ['sleep(', 'launchEnvironment', 'qaChrome', 'XCTSkip']:
            self.assertNotIn(token, source)
