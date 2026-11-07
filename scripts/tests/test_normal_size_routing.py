from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class NormalSizeRoutingTests(unittest.TestCase):
    def test_normal_and_original_methods_are_distinct(self):
        source = (ROOT / 'AteUITests/JournalOpenStateUITests.swift').read_text()
        self.assertIn("func testManualSaveFailureVisibleAtXXXL(", source)
        self.assertIn("func testManualSaveFailureVisibleAtNormalText(", source)
        self.assertIn("func testJournalRootAddAtMaximumAccessibilitySizeAndSidebarRoundTrip(", source)
        self.assertIn("func testJournalRootAddAtNormalTextAndSidebarRoundTrip(", source)
        self.assertIn("func testTimelineFixtureAtLargestTextSizeKeepsRowAndFilterReachable(", source)
        self.assertIn("func testTimelineFixtureAtNormalTextKeepsRowAndFilterReachable(", source)
        self.assertIn("func testTimelineFixtureAtLargestTextSizeLastRowClearsSearchBar(", source)
        self.assertIn("func testTimelineFixtureAtNormalTextLastRowClearsSearchBar(", source)
        source = (ROOT / 'AteUITests/CookIngredientsUITests.swift').read_text()
        self.assertIn("func testCookIngredientSheetLargeTextAccessibilityAndImperial(", source)
        self.assertIn("func testCookIngredientSheetNormalTextAccessibilityAndImperial(", source)
        self.assertIn("func testCookTimerCardLargeText(", source)
        self.assertIn("func testCookTimerCardNormalText(", source)
        source = (ROOT / 'AteUITests/SettingsOrganizationUITests.swift').read_text()
        self.assertIn("func testSyncSummaryLargestDynamicType(", source)
        self.assertIn("func testSyncSummaryNormalText(", source)
    def test_normal_audit_remains_required(self):
        source = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/AccessibilityAuditUITests/testAuditNutritionScreensWithoutDynamicType', source)
        self.assertIn("AccessibilityAuditUITests testAuditNutritionScreensWithoutDynamicType]' passed", source)
