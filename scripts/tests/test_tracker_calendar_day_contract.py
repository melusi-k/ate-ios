"""Keep day/foreground invalidation wired to the snapshot used by the grid."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[2]
UI_SHA256 = "9476f761691f6967110957df448ea4d114aa9c3d6e5a12ab695ddd6fe2617e8e"


class TrackerCalendarDayContract(unittest.TestCase):
    def test_notification_and_foreground_share_the_rendered_day_state(self):
        view = (ROOT / "Ate/Views/CookingTrackerView.swift").read_text()
        self.assertIn("@State private var calendarState = CookingTrackerCalendarState()", view)
        self.assertIn("let isToday = calendarState.isToday(date, calendar: calendar)", view)
        self.assertIn("calendar.isDate(displayedMonth, equalTo: calendarState.now, toGranularity: .month)", view)
        self.assertIn(".onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in\n            refreshCalendarDay()", view)
        self.assertIn(".onChange(of: scenePhase) { _, phase in\n            if phase == .active { refreshCalendarDay() }", view)
        self.assertIn(".onAppear { refreshCalendarDay() }", view)
        self.assertIn("calendarState.refresh(now: Date(), calendar: calendar)", view)
        self.assertNotIn("Timer", view)
        self.assertNotIn("isDateInToday", view)

    def test_existing_today_ui_journey_is_byte_unchanged(self):
        path = "AteUITests/CookingTrackerEntryUITests.swift"
        self.assertEqual(UI_SHA256, hashlib.sha256((ROOT / path).read_bytes()).hexdigest())

    def test_native_tests_cover_day_month_foreground_and_browsing(self):
        tests = (ROOT / "AteTests/CookingTrackerCalendarStateTests.swift").read_text()
        for name in ["testDayChangeRefreshMovesTodayWithoutChangingBrowsedMonthOrEventDates", "testForegroundCatchUpAcrossMonthAndYearFollowsPreviouslyCurrentMonth", "testForegroundRefreshKeepsOlderHistorySelectionMonth", "testRepeatedRefreshIsIdempotentAndBackwardClockChangeUpdatesToday"]:
            self.assertIn("func " + name + "()", tests)
