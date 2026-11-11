import XCTest
@testable import Ate

/// A canonical owner can use a different persisted domain from the legacy singleton.
/// Consumers must read that same owner rather than silently showing unrelated history.
final class CanonicalCookingConsumerTests: XCTestCase {
    private func history(_ suite: String) throws -> (CookingHistory, UserDefaults, Calendar) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return (CookingHistory(calendar: calendar, defaults: defaults), defaults, calendar)
    }

    func testCookedCollectionUsesInjectedHistoryForMembershipAndOrder() throws {
        let suite = "CanonicalCookingConsumer-\(UUID().uuidString)"
        let (history, defaults, calendar) = try history(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        var older = RecipeCard(title: "Older")
        older.id = "canonical-older-\(UUID().uuidString)"
        var newer = RecipeCard(title: "Newer")
        newer.id = "canonical-newer-\(UUID().uuidString)"
        let uncooked = RecipeCard(title: "Never cooked")
        history.record(recipeID: older.id, date: day.addingTimeInterval(-86400))
        history.record(recipeID: newer.id, date: day)
        var filter = RecipeFilter()
        filter.collection = .cookedMeals
        XCTAssertEqual(filter.apply([older, uncooked, newer], history: history).map(\.id), [newer.id, older.id])
        XCTAssertFalse(filter.matches(uncooked, history: history))
        XCTAssertTrue(filter.matches(newer, history: history))
    }

    func testWidgetSnapshotUsesInjectedHistoryWithoutConsultingSingleton() throws {
        let suite = "CanonicalCookingWidget-\(UUID().uuidString)"
        let (history, defaults, calendar) = try history(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        history.record(recipeID: "canonical-today", date: day)
        history.record(recipeID: "canonical-yesterday", date: day.addingTimeInterval(-86400))
        let snapshot = WidgetSnapshotBuilder.build(recipes: [], shopping: [], health: nil,
                                                   now: day, calendar: calendar, history: history)
        XCTAssertTrue(snapshot.cookedToday)
        XCTAssertEqual(snapshot.cookingStreak, 2)
    }
}
