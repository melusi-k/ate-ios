"""Static identity/gesture preservation, not a substitute for UI execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class UIAssertionContractTests(unittest.TestCase):
    def test_quality_heading_not_action_container_owns_panel_identifier(self):
        source = (ROOT / 'Ate/Views/AddRecipeSheet.swift').read_text()
        panel = source.split('Label("Draft, needs your input"', 1)[1].split('if let n = draft?.aiNote', 1)[0]
        self.assertLess(panel.index('.accessibilityIdentifier("draftNeedsInput")'), panel.index('if (d.aiConfidence'))
        self.assertIn('.accessibilityIdentifier("repairDraftQuality")', panel)
        self.assertIn('.accessibilityIdentifier("confirmDraft")', panel)
        self.assertNotIn('.sheetCard(Theme.warm.opacity(0.5))\n            .accessibilityIdentifier', panel)

    def test_header_reveal_retains_strict_journal_tab_and_header_assertions(self):
        source = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        method = source.split('func testNavigationHeadersRemainStableOnShoppingAndSettings()', 1)[1]
        self.assertLess(method.index('settingsTab.tap()'), method.index('tab("Journal")'))
        self.assertIn('XCTAssertTrue(settingsTab.isHittable', method)
        self.assertEqual(method.count('settingsTab.tap()'), 1)
        for text in ['Journal must have one navigation header', 'Scrolling Journal must not introduce a duplicate header',
                     'Journal New entry must stay reachable after scrolling']:
            self.assertIn(text, method)
        helper = source.split('func tab(_ name: String)', 1)[1].split('func startPrompt', 1)[0]
        self.assertIn('Journal must be selected through its tab, not a pushed-screen back button', helper)
        self.assertIn('Selected Journal tab must show the Journal root', helper)

    def test_original_repair_wait_and_real_action_are_retained(self):
        source = (ROOT / 'AteUITests/DraftQualityRepairUITests.swift').read_text()
        self.assertIn('repair.waitForExistence(timeout: 15)', source)
        self.assertIn('repair.tap()', source)
        self.assertIn('waitForExpectations(timeout: 15)', source)
        self.assertIn('XCTAssertFalse(app.buttons["saveRecipe"].isEnabled', source)
        self.assertIn('XCTAssertTrue(app.buttons["saveRecipe"].isEnabled', source)
