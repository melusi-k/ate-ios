import XCTest
@testable import Ate

final class CookingTrackerCalendarStateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Africa/Johannesburg")!
        return value
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDayChangeRefreshMovesTodayWithoutChangingBrowsedMonthOrEventDates() {
        let before = date(11, 15, 23, 59)
        let after = date(11, 16, 0, 1)
        var state = CookingTrackerCalendarState(now: before, calendar: calendar)
        let month = state.displayedMonth
        XCTAssertTrue(state.isToday(before, calendar: calendar))
        XCTAssertFalse(state.isToday(after, calendar: calendar))
        state.refresh(now: after, calendar: calendar)
        XCTAssertFalse(state.isToday(before, calendar: calendar))
        XCTAssertTrue(state.isToday(after, calendar: calendar))
        XCTAssertEqual(state.now, after)
        XCTAssertEqual(state.displayedMonth, month)
        XCTAssertEqual(calendar.component(.day, from: before), 15)
    }

    func testForegroundCatchUpAcrossMonthAndYearFollowsPreviouslyCurrentMonth() {
        let before = date(12, 31, 23, 58)
        let after = date(1, 2, 8, 0, year: 2027)
        var state = CookingTrackerCalendarState(now: before, calendar: calendar)
        state.refresh(now: after, calendar: calendar)
        XCTAssertTrue(state.isToday(after, calendar: calendar))
        XCTAssertFalse(state.isToday(before, calendar: calendar))
        XCTAssertEqual(state.displayedMonth, calendar.dateInterval(of: .month, for: after)?.start)
    }

    func testForegroundRefreshKeepsOlderHistorySelectionMonth() {
        let before = date(11, 30, 23, 59)
        let after = date(12, 1, 0, 1)
        var state = CookingTrackerCalendarState(now: before, calendar: calendar)
        let older = date(9, 1, 0, 0)
        state.displayedMonth = older
        state.refresh(now: after, calendar: calendar)
        XCTAssertEqual(state.displayedMonth, older)
        XCTAssertTrue(state.isToday(after, calendar: calendar))
        XCTAssertFalse(state.isToday(before, calendar: calendar))
    }

    func testRepeatedRefreshIsIdempotentAndBackwardClockChangeUpdatesToday() {
        let later = date(11, 16, 0, 1)
        let earlier = date(11, 15, 23, 59)
        var state = CookingTrackerCalendarState(now: later, calendar: calendar)
        state.refresh(now: earlier, calendar: calendar)
        let refreshed = state
        state.refresh(now: earlier, calendar: calendar)
        XCTAssertEqual(state, refreshed)
        XCTAssertTrue(state.isToday(earlier, calendar: calendar))
        XCTAssertFalse(state.isToday(later, calendar: calendar))
    }
}
