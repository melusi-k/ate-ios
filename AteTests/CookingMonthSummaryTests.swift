import XCTest
@testable import Ate

final class CookingMonthSummaryTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }
    private func month(_ year: Int, _ month: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 15, hour: 12)))
    }
    func testCountsDaysAndDistinctRecipeIDsNotMealsOrRepeatedCooks() throws {
        let calendar = try calendar()
        let summary = CookingMonthSummary.make(events: ["2026-11-01": ["r1", "r2"], "2026-11-02": ["r1"],
            "2026-11-03": ["deleted-recipe"], "2026-10-31": ["outside"]], month: try month(2026, 11, calendar: calendar), calendar: calendar)
        XCTAssertEqual(summary, .init(cookingDays: 3, distinctRecipes: 3))
        XCTAssertEqual(summary.text, "3 cooking days · 3 distinct recipes")
    }
    func testMonthYearAndLeapBoundariesDoNotCountMalformedOrEmptyDays() throws {
        let calendar = try calendar()
        let events: [String: Set<String>] = ["2024-02-29": ["leap"], "2024-03-01": ["march"], "2024-02-30": ["invalid"],
            "2024-2-01": ["noncanonical"], "2024-02-00": ["zero"], "2024-02-01": [], "2024-02-02": ["", " "],
            "2023-12-31": ["last"], "2024-01-01": ["new"]]
        let leap = CookingMonthSummary.make(events: events, month: try month(2024, 2, calendar: calendar), calendar: calendar)
        XCTAssertEqual(leap, .init(cookingDays: 1, distinctRecipes: 1))
        XCTAssertEqual(leap.text, "1 cooking day · 1 distinct recipe")
        XCTAssertEqual(CookingMonthSummary.make(events: events, month: try month(2023, 12, calendar: calendar), calendar: calendar).distinctRecipes, 1)
        XCTAssertEqual(CookingMonthSummary.make(events: events, month: try month(2024, 1, calendar: calendar), calendar: calendar).distinctRecipes, 1)
    }
    func testStoredLocalDayMonthStableAcrossTimeZonesAndEmptyHistoryExplicit() throws {
        let events: [String: Set<String>] = ["2026-11-01": ["first"], "2026-11-30": ["last"], "2026-12-01": ["next"]]
        for zone in ["UTC", "Pacific/Honolulu", "Pacific/Kiritimati", "Africa/Johannesburg"] {
            let calendar = try calendar(zone)
            XCTAssertEqual(CookingMonthSummary.make(events: events, month: try month(2026, 11, calendar: calendar), calendar: calendar),
                           .init(cookingDays: 2, distinctRecipes: 2), zone)
        }
        let calendar = try calendar()
        let empty = CookingMonthSummary.make(events: [:], month: try month(2026, 11, calendar: calendar), calendar: calendar)
        XCTAssertEqual(empty.text, "0 cooking days · 0 distinct recipes")
    }
}
