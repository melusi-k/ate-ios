import XCTest
@testable import Ate

final class CookingHistoryTests: XCTestCase {
    private let suiteName = "CookingHistoryTests"

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

    func testKeyRoundTrips() {
        let (history, cal) = makeHistory()
        let d = cal.date(from: DateComponents(year: 2026, month: 1, day: 9))!
        XCTAssertEqual(history.date(for: history.key(for: d)), d)
    }
}
