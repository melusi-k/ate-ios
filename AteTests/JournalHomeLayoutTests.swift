import XCTest
@testable import Ate

final class JournalHomeLayoutTests: XCTestCase {
    func testOneExplicitGapAndMeasuredBottomBandWithClearance() {
        XCTAssertEqual(JournalHomeMetrics.sectionGap, 12)
        XCTAssertEqual(JournalHomeMetrics.bottomMargin(listBottomY: 844, chromeMinY: 690), 166)
        XCTAssertEqual(JournalHomeMetrics.bottomMargin(listBottomY: 390, chromeMinY: 300), 102)
        XCTAssertEqual(JournalHomeMetrics.bottomMargin(listBottomY: 600, chromeMinY: 610), 12)
        XCTAssertEqual(JournalHomeMetrics.bottomMargin(listBottomY: nil, chromeMinY: 690), 0)
        XCTAssertEqual(JournalHomeMetrics.bottomMargin(listBottomY: 844, chromeMinY: nil), 0)
    }
}
