import Foundation

/// A renderable calendar snapshot. Notifications refresh this value rather than
/// relying on a fresh Date() read in a SwiftUI body that may never be invalidated.
struct CookingTrackerCalendarState: Equatable {
    private(set) var now: Date
    var displayedMonth: Date

    init(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        self.now = now
        displayedMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
    }

    func isToday(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    /// Follow a month rollover only when looking at the previously current month.
    /// Browsing older history must not jump back to the current month on foreground.
    mutating func refresh(now newNow: Date, calendar: Calendar = .autoupdatingCurrent) {
        if calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month) {
            displayedMonth = calendar.dateInterval(of: .month, for: newNow)?.start ?? newNow
        }
        now = newNow
    }
}
