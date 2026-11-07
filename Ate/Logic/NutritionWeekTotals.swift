import Foundation

/// Week scoping for diary totals. Membership uses each entry's persisted local day
/// (dayKey), matching how the diary itself groups days, so a week total stays stable
/// regardless of the time zone the device is in later.
enum NutritionWeekTotals {
    static func weekInterval(containing date: Date, calendar: Calendar = .autoupdatingCurrent) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    static func entries(_ entries: [NutritionDiaryEntry], inWeekOf date: Date,
                        calendar: Calendar = .autoupdatingCurrent) -> [NutritionDiaryEntry] {
        guard let week = weekInterval(containing: date, calendar: calendar) else { return [] }
        return entries.filter { entry in
            guard let day = NutritionDiaryDayKey.date(for: entry.dayKey, calendar: calendar) else { return false }
            // Half-open membership made explicit rather than relying on DateInterval
            // semantics: the first instant of the following week belongs to that
            // week, never to this one.
            return day >= week.start && day < week.end
        }
    }

    static func calculate(entries: [NutritionDiaryEntry], inWeekOf date: Date,
                          calendar: Calendar = .autoupdatingCurrent) -> NutritionDayTotals {
        NutritionDayTotals.calculate(entries: self.entries(entries, inWeekOf: date, calendar: calendar))
    }
}
