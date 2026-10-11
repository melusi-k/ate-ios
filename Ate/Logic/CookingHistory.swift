import Foundation

/// Local cooking events. A recipe keeps only its last-cooked timestamp, so this service preserves the
/// day-level history needed for streaks and the Insights calendar without changing sync payloads.
final class CookingHistory {
    static let shared = CookingHistory()
    private static let key = "ate.cooking.history.v1"
    private(set) var events: [String: Set<String>] = [:] // day key -> recipe IDs
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            events = decoded.mapValues(Set.init)
        }
    }

    func record(recipeID: String, date: Date = Date()) {
        let day = key(for: date)
        events[day, default: []].insert(recipeID)
        save()
    }

    func recipeIDs(on date: Date) -> Set<String> { events[key(for: date)] ?? [] }
    func cooked(on date: Date) -> Bool { !recipeIDs(on: date).isEmpty }
    func clear() { events.removeAll(); save() }

    func days(in interval: DateInterval) -> Set<String> {
        Set(events.keys.filter { guard let d = date(for: $0) else { return false }; return interval.contains(d) })
    }

    func streak(asOf date: Date = Date()) -> Int {
        var cursor = calendar.startOfDay(for: date)
        // A streak may still be alive if today has not happened yet.
        if !cooked(on: cursor), let previous = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = previous }
        var count = 0
        while cooked(on: cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func date(for key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    private func save() {
        let value = events.mapValues { Array($0).sorted() }
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: Self.key)
    }
}
