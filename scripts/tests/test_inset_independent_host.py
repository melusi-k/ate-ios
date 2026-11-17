from approved_merge_539 import normalize
from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
MEASUREMENT='        .background(GeometryReader { geometry in\n            Color.clear.preference(key: RecipeDetailHostBottomYKey.self,\n                                   value: geometry.frame(in: .global).maxY)\n        })\n        .onPreferenceChange(RecipeDetailHostBottomYKey.self) { value in\n            #if DEBUG\n            QA8DetailLayoutDiagnostic.event("detail-host-bottom", value: value.map { Double($0) },\n                previous: hostBottomY.map { Double($0) }, reserve: Double(footerChromeReserve))\n            #endif\n            hostBottomY = value\n        }\n'
COMMENT='        // Measure the outer inset host, not the content region reduced by the\n        // reserve that this measurement controls. Keep live parent/chrome changes.\n'
def restore_host_measurement(test,source):
    test.assertEqual(source.count(COMMENT+MEASUREMENT),1)
    source=source.replace(COMMENT+MEASUREMENT,'',1)
    anchor='        .toolbar(.hidden'
    test.assertEqual(source.count(anchor),1)
    return source.replace(anchor,MEASUREMENT+anchor,1)
class InsetIndependentHostTests(unittest.TestCase):
    def test_entire_original_source_restores_after_measurement_reorder(self):
        source=normalize('source:Ate/Views/RecipeDetailView.swift', (ROOT/'Ate/Views/RecipeDetailView.swift').read_text())
        self.assertEqual(hashlib.sha256(restore_host_measurement(self,source).encode()).hexdigest(), '4f65e8f3c0210c37aa03f7d1b7c2cf1b9998be766087c5ec64c8c2ec2fefff45')
    def test_measurement_wraps_safe_area_inset_not_reduced_content(self):
        source=normalize('source:Ate/Views/RecipeDetailView.swift', (ROOT/'Ate/Views/RecipeDetailView.swift').read_text())
        inset=source.index('.safeAreaInset(edge: .bottom')
        measure=source.index('.background(GeometryReader { geometry in')
        self.assertLess(inset,measure)
        self.assertIn('return max(0, hostBottomY - bottomChromeMinY) + 8',source)
        self.assertIn('hostBottomY = value',source)
        self.assertNotIn('DispatchQueue.main.asyncAfter',source)
    def test_live_outer_geometry_gives_stable_clearance_without_freezing_changes(self):
        reserve=lambda host,chrome:max(0,host-chrome)+8
        self.assertEqual([reserve(760,740) for _ in range(10)],[28]*10)
        self.assertEqual(reserve(760,700),68)
        self.assertEqual(reserve(680,700),8)
        self.assertEqual(reserve(800,740),68)
