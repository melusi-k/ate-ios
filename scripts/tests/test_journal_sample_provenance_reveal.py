"""Source bounds only; actual Journal viewport requires native verification."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class JournalSampleProvenanceRevealTests(unittest.TestCase):
    def test_provenance_uses_text_and_scrolls_towards_viewport(self):
        source = (ROOT / 'AteUITests/InsightsAcceptanceUITests.swift').read_text()
        journey = source.split('func testJournalRootReflectionLabelsSampleHealthPrompts()', 1)[1].split('private func launchSeededDestinations', 1)[0]
        for expected in ['app.staticTexts.matching(identifier: "journal.reflection.sampleBadge")',
                         'XCTAssertEqual(badges.count, 1', 'XCTAssertEqual(badge.label, "Sample data")',
                         'while !badge.isHittable && swipes < 6', 'if badge.frame.midY < top',
                         'app.swipeDown()', 'app.swipeUp()', 'XCTAssertTrue(badge.isHittable',
                         'XCTAssertGreaterThanOrEqual(badge.frame.minY, headerBottom',
                         'XCTAssertLessThanOrEqual(badge.frame.maxY, app.tabBars.firstMatch.frame.minY']:
            self.assertIn(expected, journey)
        self.assertNotIn('reveal(badge)', journey)
        self.assertIn('let prompt = app.buttons["insights.prompt"].firstMatch', journey)
        self.assertIn('wait(badge, 15)', journey)
