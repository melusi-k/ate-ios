"""Keep owner-descoped Dynamic Type coverage out of the active PR gates."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class DynamicTypeRoutingTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text()

    def test_compile_retains_normal_nutrition_and_excludes_cross_size_cases(self):
        source = self.read(".github/workflows/compile-check.yml")
        selected = [line.strip().rstrip(chr(92)).rstrip() for line in source.splitlines() if "-only-testing:" in line]
        self.assertIn("-only-testing:AteUITests/AccessibilityAuditUITests/testAuditNutritionScreensWithoutDynamicType", selected)
        self.assertIn("-only-testing:AteUITests/NutritionDiaryUITests", selected)
        self.assertIn("-only-testing:AteUITests/NutritionGoalsUITests", selected)
        self.assertFalse(any("LargestDynamicType" in x or "FontScaling" in x or "LiveDynamicType" in x for x in selected))
        for method in ("testCookIngredientSheetLargeTextAccessibilityAndImperial", "testCookTimerCardLargeText"):
            self.assertIn("-skip-testing:AteUITests/CookIngredientsUITests/" + method, source)
            self.assertNotIn(method + "]' passed", source)

    def test_journal_keeps_normal_class_and_excludes_large_text(self):
        source = self.read(".github/workflows/journal-open-state-ui.yml")
        self.assertIn("-only-testing:AteUITests/JournalOpenStateUITests", source)
        for method in ("testManualSaveFailureVisibleAtXXXL", "testJournalRootAddAtMaximumAccessibilitySizeAndSidebarRoundTrip", "testTimelineFixtureAtLargestTextSizeKeepsRowAndFilterReachable", "testTimelineFixtureAtLargestTextSizeLastRowClearsSearchBar"):
            self.assertIn("-skip-testing:AteUITests/JournalOpenStateUITests/" + method, source)

    def test_optional_is_dispatch_only_and_not_a_required_dependency(self):
        source = self.read(".github/workflows/optional-dynamic-type.yml")
        triggers = source.split("on:\n", 1)[1].split("\njobs:", 1)[0]
        self.assertEqual(triggers.strip(), "workflow_dispatch:")
        self.assertNotIn("continue-on-error", source)
        for method in ("testAuditNutritionScreens", "testLiveDynamicTypeToggle", "testCookTimerCardLargeText", "testManualSaveFailureVisibleAtXXXL"):
            self.assertIn("-only-testing:AteUITests/", source)
            self.assertIn(method, source)
        for path in ("compile-check.yml", "journal-open-state-ui.yml", "dogfood-qualification.yml"):
            self.assertNotIn("optional-dynamic-type", self.read(".github/workflows/" + path))

    def test_original_audit_preserved_and_normal_audit_excludes_only_dynamic_type(self):
        source = self.read("AteUITests/AccessibilityAuditUITests.swift")
        self.assertIn("try auditNutritionScreens(types: .all)", source)
        self.assertIn("XCUIAccessibilityAuditType.all.subtracting(.dynamicType)", source)
        self.assertIn("performAccessibilityAudit(for: types)", source)
        self.assertIn("if issue.auditType == .contrast { return true }", source)


if __name__ == "__main__":
    unittest.main()
