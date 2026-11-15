from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class Merge537Layout(unittest.TestCase):
    def test_single_cook_footer_sibling_preserves_measured_reserve(self):
        s=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        self.assertEqual(s.count('Label("Cook mode", systemImage: "frying.pan")'),1)
        self.assertEqual(s.count('store.beginCookSession(recipeID: recipeID, factor: factor)'),1)
        self.assertEqual(s.count('.accessibilityIdentifier("recipe.detail.scroll")'),1)
        self.assertIn('VStack(spacing: 0) {\n                    ScrollView {',s)
        self.assertIn('.contentShape(Rectangle())\n                    .clipped()',s)
        self.assertLess(s.index('.clipped()'),s.index('Label("Cook mode"'))
        self.assertIn('.padding(.bottom, footerChromeReserve)',s)
        self.assertIn('max(0, hostBottomY - bottomChromeMinY) + 8',s)
        self.assertNotIn('.safeAreaInset(edge: .bottom',s)
    def test_all_dogfood_native_selections_and_named_passes_remain(self):
        s=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        for name in ['test28_GroupSortAndMenus','test29_ReorderMyOrder','test29b_ReorderMyOrderActions',
                     'testQA1_AddFromURL_JSONLD','testQA1_AddFromURL_InstagramCaption','testQA1_AddFromURL_HiddenCaptionFallback',
                     'testQA2_AddFromPhoto','testQA3_GenerateAndEdit','testQA4_Save','testQA5_Share','testQA6_OpenShared','testQA8_Timers']:
            self.assertIn('/'+name+' \\',s)
            self.assertIn(name+"]' passed",s)
        self.assertIn('steps.library_flows.outcome',s)
        self.assertIn('steps.critical_flows.outcome',s)
        self.assertIn('"$total" -lt 12',s)
        self.assertIn('-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 480',s)
