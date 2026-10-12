import XCTest
@testable import Ate

final class CookingHistoryTests: XCTestCase {
    private let suiteName = "CookingHistoryTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeHistory() -> (CookingHistory, Calendar) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return (CookingHistory(calendar: cal, defaults: UserDefaults(suiteName: suiteName)!), cal)
    }

    func testRecordDeduplicatesRecipePerDayAndBuildsStreak() {
        let (history, cal) = makeHistory()
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        history.record(recipeID: "r1", date: d.addingTimeInterval(3600))
        history.record(recipeID: "r1", date: d.addingTimeInterval(7200))
        history.record(recipeID: "r2", date: cal.date(byAdding: .day, value: -1, to: d)!)
        XCTAssertEqual(history.recipeIDs(on: d), ["r1"])
        XCTAssertEqual(history.streak(asOf: d.addingTimeInterval(12 * 3600)), 2)
        history.clear()
        XCTAssertEqual(history.streak(asOf: d), 0)
    }

    func testHistoryPersistsAcrossInstancesWithoutUsingStandardDefaults() {
        let (history, cal) = makeHistory()
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        history.record(recipeID: "r1", date: d)
        history.record(recipeID: "r2", date: d)

        let reloaded = CookingHistory(calendar: cal, defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(reloaded.recipeIDs(on: d), ["r1", "r2"])
        XCTAssertTrue(reloaded.cooked(on: d))
    }

    func testStreakAllowsYesterdayButBreaksAcrossGap() {
        let (history, cal) = makeHistory()
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        history.record(recipeID: "yesterday", date: yesterday)
        XCTAssertEqual(history.streak(asOf: today.addingTimeInterval(12 * 3600)), 1)
        history.record(recipeID: "older", date: threeDaysAgo)
        XCTAssertEqual(history.streak(asOf: today.addingTimeInterval(12 * 3600)), 1)
    }

    func testEmptyHistoryHasNoStreakAndTodayStartsOneDayStreak() {
        let (history, cal) = makeHistory()
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        XCTAssertEqual(history.streak(asOf: today.addingTimeInterval(12 * 3600)), 0)

        history.record(recipeID: "today-r1", date: today.addingTimeInterval(3600))
        history.record(recipeID: "today-r2", date: today.addingTimeInterval(7200))
        XCTAssertEqual(history.streak(asOf: today.addingTimeInterval(12 * 3600)), 1)
        XCTAssertEqual(history.recipeIDs(on: today), ["today-r1", "today-r2"])
    }

    func testStreakCrossesMonthYearAndLeapDayBoundaries() {
        let (history, cal) = makeHistory()
        let dates = [
            cal.date(from: DateComponents(year: 2024, month: 2, day: 28))!,
            cal.date(from: DateComponents(year: 2024, month: 2, day: 29))!,
            cal.date(from: DateComponents(year: 2024, month: 3, day: 1))!,
            cal.date(from: DateComponents(year: 2024, month: 12, day: 31))!,
            cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        ]
        for (index, date) in dates.enumerated() {
            if index < 3 { history.record(recipeID: "leap-\\(index)", date: date) }
        }
        XCTAssertEqual(history.streak(asOf: dates[2].addingTimeInterval(12 * 3600)), 3)

        history.clear()
        history.record(recipeID: "year-end", date: dates[3])
        history.record(recipeID: "new-year", date: dates[4])
        XCTAssertEqual(history.streak(asOf: dates[4].addingTimeInterval(12 * 3600)), 2)
    }

    func testLocalDayKeysRemainStableAcrossTimezoneChange() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let defaults = UserDefaults(suiteName: suiteName)!
        let history = CookingHistory(calendar: newYork, defaults: defaults)
        // 2026-10-12 03:30 UTC is still the previous local day in New York.
        let instant = ISO8601DateFormatter().date(from: "2026-10-12T03:30:00Z")!
        let recordedDay = newYork.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        history.record(recipeID: "timezone-recipe", date: instant)
        XCTAssertEqual(history.recipeIDs(on: recordedDay), ["timezone-recipe"])

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let reopened = CookingHistory(calendar: losAngeles, defaults: defaults)
        let sameStoredDay = losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        XCTAssertEqual(reopened.recipeIDs(on: sameStoredDay), ["timezone-recipe"])
    }

    func testKeyRoundTrips() {
        let (history, cal) = makeHistory()
        let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 9))!
        XCTAssertEqual(history.date(for: history.key(for: d)), d)
    }
}
