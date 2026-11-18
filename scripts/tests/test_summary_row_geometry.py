from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class SummaryRowGeometryTests(unittest.TestCase):
    def test_text_and_padded_row_have_distinct_targets(self):
        source = (ROOT / 'Ate/Views/CookingTrackerView.swift').read_text()
        row = source.split('let monthSummary = CookingMonthSummary.make', 1)[1].split('LazyVGrid', 1)[0]
        self.assertLess(row.index('.accessibilityIdentifier("tracker.monthSummary")'), row.index('.padding(.vertical, 12)'))
        self.assertIn('.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)', row)
        self.assertIn('.accessibilityElement(children: .contain)', row)
        self.assertIn('.accessibilityIdentifier("tracker.monthSummaryRow")', row)
        test = (ROOT / 'AteUITests/CookingTrackerEntryUITests.swift').read_text()
        self.assertIn('app.otherElements.matching(identifier: "tracker.monthSummaryRow")', test)
        self.assertIn('XCTAssertEqual(rows.count, 1', test)
        self.assertIn('XCTAssertGreaterThanOrEqual(row.frame.height, 43.99', test)
        self.assertIn('XCTAssertEqual(summary.label, "Recorded this month: 0 days cooked · 0 recipes")', test)
