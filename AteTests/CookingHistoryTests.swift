import XCTest
@testable import Ate

final class CookingHistoryTests: XCTestCase {
    func testRecordDeduplicatesRecipePerDayAndBuildsStreak() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let history = CookingHistory(calendar: cal)
        history.clear()
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        history.record(recipeID: "r1", date: d.addingTimeInterval(3600))
        history.record(recipeID: "r1", date: d.addingTimeInterval(7200))
        history.record(recipeID: "r2", date: cal.date(byAdding: .day, value: -1, to: d)!)
        XCTAssertEqual(history.recipeIDs(on: d), ["r1"])
        XCTAssertEqual(history.streak(asOf: d.addingTimeInterval(12 * 3600)), 2)
        history.clear()
        XCTAssertEqual(history.streak(asOf: d), 0)
    }

    func testKeyRoundTrips() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let history = CookingHistory(calendar: cal)
        let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 9))!
        XCTAssertEqual(history.date(for: history.key(for: d)), d)
    }
}
