import Foundation

/// Library "Group by" + "Sort" choice (persisted). Pure logic so it's unit-tested.
struct LibraryLayout: Codable, Equatable {
    enum GroupBy: String, Codable, CaseIterable, Identifiable {
        case none = "None", added = "Recently added", cuisine = "Cuisine", mainIngredient = "Main ingredient", cookTime = "Cook time"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .none: return "list.bullet"; case .added: return "calendar"; case .cuisine: return "globe.europe.africa"
            case .mainIngredient: return "leaf"; case .cookTime: return "clock"
            }
        }
    }
    enum SortBy: String, Codable, CaseIterable, Identifiable {
        case newest = "Newest", az = "A–Z", quickest = "Quickest", recentlyCooked = "Recently cooked"
        case favouritesFirst = "Favourites first", myOrder = "My order"
        var id: String { rawValue }
    }

    var group: GroupBy = .none
    var sort: SortBy = .newest

    struct Section: Identifiable, Equatable {
        let title: String
        let recipes: [RecipeCard]
        var id: String { title }
    }

    func sorted(_ rs: [RecipeCard]) -> [RecipeCard] {
        // Stable tiebreak: newest first, then id.
        let newest: (RecipeCard, RecipeCard) -> Bool = { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id < $1.id }
        switch sort {
        case .newest: return rs.sorted(by: newest)
        case .az: return rs.sorted { let c = $0.title.localizedCaseInsensitiveCompare($1.title); return c == .orderedSame ? newest($0, $1) : c == .orderedAscending }
        case .quickest: return rs.sorted { a, b in
            let x = a.timeMinutes.flatMap { $0 > 0 ? $0 : nil } ?? .max, y = b.timeMinutes.flatMap { $0 > 0 ? $0 : nil } ?? .max
            return x != y ? x < y : newest(a, b) }
        case .recentlyCooked: return rs.sorted { a, b in
            let x = a.lastCookedAt ?? 0, y = b.lastCookedAt ?? 0
            return x != y ? x > y : newest(a, b) }
        case .favouritesFirst: return rs.sorted { a, b in a.favorite != b.favorite ? a.favorite : newest(a, b) }
        case .myOrder: return rs.sorted { a, b in
            // Never-ordered cards (nil) go first, newest first, so new saves are easy to find.
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?): return x != y ? x < y : newest(a, b)
            case (nil, nil): return newest(a, b)
            case (nil, _): return true
            case (_, nil): return false
            } }
        }
    }

    static func cookTimeBucket(_ m: Int?) -> String {
        guard let m, m > 0 else { return "No time given" }
        switch m { case ...15: return "15 min or less"; case ...30: return "Under 30 min"; case ...60: return "Under an hour"; default: return "Over an hour" }
    }
    static let cookTimeOrder = ["15 min or less", "Under 30 min", "Under an hour", "Over an hour", "No time given"]

    static func addedBucket(_ ms: Double, now: Date, calendar: Calendar) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(d) { return "This week" }
        if d > now.addingTimeInterval(-7 * 86_400) { return "This week" }
        return "Earlier"
    }

    func key(for r: RecipeCard, now: Date, calendar: Calendar) -> String {
        switch group {
        case .none: return ""
        case .added: return Self.addedBucket(r.createdAt, now: now, calendar: calendar)
        case .cuisine: return r.cuisine.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Other"
        case .mainIngredient: return IngredientTags.main(for: r).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Other"
        case .cookTime: return Self.cookTimeBucket(r.timeMinutes)
        }
    }

    /// Sorted, then grouped. Section order: fixed for time/added buckets, A–Z otherwise ("Other" last).
    func sections(_ rs: [RecipeCard], now: Date = Date(), calendar: Calendar = .current) -> [Section] {
        let s = sorted(rs)
        guard group != .none else { return [Section(title: "", recipes: s)] }
        var order: [String] = []
        var buckets: [String: [RecipeCard]] = [:]
        for r in s {
            let k = key(for: r, now: now, calendar: calendar)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(r)
        }
        let fixed: [String]? = group == .cookTime ? Self.cookTimeOrder : group == .added ? ["Today", "This week", "Earlier"] : nil
        let titles: [String]
        if let fixed { titles = fixed.filter { buckets[$0] != nil } }
        else { titles = order.sorted { a, b in a == "Other" ? false : b == "Other" ? true : a.localizedCaseInsensitiveCompare(b) == .orderedAscending } }
        return titles.map { Section(title: $0, recipes: buckets[$0]!) }
    }

    /// Drag-to-reorder only makes sense on one flat list in "My order".
    var canReorder: Bool { sort == .myOrder && group == .none }

    /// Reordering a subset would assign colliding positions to hidden recipes. Keep it disabled
    /// until the user returns to the complete, unfiltered library.
    func canReorder(showingCount: Int, recipeCount: Int, hasSearch: Bool, hasFilter: Bool) -> Bool {
        canReorder && !hasSearch && !hasFilter && showingCount == recipeCount
    }

    static let key = "ate.libraryLayout.v1"
    static func load(_ d: UserDefaults = .standard) -> LibraryLayout {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(LibraryLayout.self, from: $0) } ?? LibraryLayout()
    }
    func save(_ d: UserDefaults = .standard) { d.set(try? JSONEncoder().encode(self), forKey: Self.key) }
}
