from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
# SHA256 pin from reviewed main 4abdad968cd563f9d2f3e3dbb562fec5f6bf8edd; no git history required.
class InsightsOrderAccessibilityContracts(unittest.TestCase):
    def test_only_reviewed_geometry_animation_and_identifiers_change(self):
        raw=(ROOT/'Ate/Views/InsightsView.swift').read_text()
        restored=raw.replace('withAnimation(Motion.anim(.snappy)) { isEditingInsightOrder.toggle() }','withAnimation(.snappy) { isEditingInsightOrder.toggle() }',1)
        for direction in ['up','down']:
            fragment='Image(systemName: "arrow.'+direction+'").frame(width: 44, height: 44)\n                                            .contentShape(Rectangle())'
            self.assertEqual(restored.count(fragment),1)
            restored=restored.replace(fragment,'Image(systemName: "arrow.'+direction+'").frame(width: 36, height: 36)',1)
            identifier='\n                                    .accessibilityIdentifier("insights.order.'+direction+'.\\(tileID)")'
            self.assertEqual(restored.count(identifier),1);restored=restored.replace(identifier,'',1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), 'a0e97937609d384c4a9cc61c4622cd2bac9db83c361e03a512b41d2e2c65089e')
    def test_shared_motion_helper_remains_reduce_motion_aware(self):
        theme=(ROOT/'Ate/Design/Theme.swift').read_text().split('enum Motion {',1)[1].split('\n}',1)[0]
        self.assertIn('UIAccessibility.isReduceMotionEnabled',theme)
        self.assertIn('reduce ? nil : a',theme)
        ui=(ROOT/'Ate/Views/InsightsView.swift').read_text()
        self.assertIn('withAnimation(Motion.anim(.snappy)) { isEditingInsightOrder.toggle() }',ui)
    def test_native_journey_measures_both_targets_and_actual_inverse_move(self):
        ui=(ROOT/'AteUITests/InsightsReorderAccessibilityUITests.swift').read_text()
        for check in ['XCTAssertGreaterThanOrEqual(arrow.frame.width, 44)',
                      'XCTAssertGreaterThanOrEqual(arrow.frame.height, 44)',
                      'down.tap()', 'up.tap()', 'XCTAssertFalse(up.exists']:
            self.assertIn(check,ui)
        for forbidden in ['sleep(', 'Mock', 'retry', 'launchEnvironment']:
            self.assertNotIn(forbidden,ui)
