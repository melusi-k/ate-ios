import Foundation

/// One row of the unified Food Journal timeline (#245): everything the timeline needs to group, filter and search an
/// entry, as a plain value. Building it never writes to the store and never drops an entry.
struct JournalTimelineItem: Equatable, Identifiable {
    var id: String
    var kind: JournalEntryKind
    var createdAt: Date
    /// Local YYYY-MM-DD the entry belongs to. Meals keep the day they were logged for; see `JournalTimeline.item`.
    var dayKey: String
    /// nil for reflections, and for a meal row whose payload is missing (kept visible, never dropped).
    var meal: NutritionMeal?
    var hasRecipeLink: Bool
    var searchText: String
    /// What a row shows: a reflection's text, or a meal's food name. A meal whose payload is missing shows a placeholder.
    /// Defaults to empty so existing memberwise callers compile; `item(from:payload:calendar:)` always sets it.
    var summary: String = ""
}

/// Filters named in the #245 contract: meal type, recipe-linked entries, reflections.
enum JournalTimelineFilter: Equatable {
    case all
    /// nil matches every meal entry; a value matches that meal type only.
    case meals(NutritionMeal?)
    case reflections
    case recipeLinked
}

struct JournalTimelineSection: Equatable, Identifiable {
    var dayKey: String
    var items: [JournalTimelineItem]
    var id: String { dayKey }
}

enum JournalTimeline {
    /// Builds a row from stored values. A stored `dayKey` wins (the day a meal was logged for). A row with no day key
    /// (every reflection written before #245) falls back to the local day of `createdAt` in `calendar`.
    static func item(from entry: JournalEntry, payload: JournalMealPayload?,
                     calendar: Calendar = .autoupdatingCurrent) -> JournalTimelineItem {
        var parts: [String] = [entry.text, entry.prompt, entry.locationName ?? ""]
        if let payload {
            parts.append(payload.foodName)
            if let meal = NutritionMeal(rawValue: payload.mealRaw) { parts.append(meal.title) }
        }
        if case .snapshots(let snapshots) = entry.recipeSnapshotDecoding {
            parts.append(contentsOf: snapshots.map { $0.title })
        }
        let day = entry.dayKey ?? NutritionDiaryDayKey.make(entry.createdAt, calendar: calendar)
        let isMeal = entry.kind == .meal
        let hasSnapshots: Bool
        switch entry.recipeSnapshotDecoding {
        case .snapshots(let snapshots): hasSnapshots = !snapshots.isEmpty
        case .none: hasSnapshots = false
        // Preserve unreadable bytes, but they cannot prove that a recipe was linked.
        case .undecodable: hasSnapshots = false
        }
        return JournalTimelineItem(id: entry.id, kind: entry.kind, createdAt: entry.createdAt, dayKey: day,
                                   meal: isMeal ? payload.flatMap { NutritionMeal(rawValue: $0.mealRaw) } : nil,
                                   hasRecipeLink: !entry.recipeIDs.isEmpty || hasSnapshots,
                                   searchText: parts.joined(separator: " "),
                                   summary: isMeal ? (payload?.foodName ?? "Meal details unavailable") : entry.text)
    }

    static func matches(_ item: JournalTimelineItem, filter: JournalTimelineFilter) -> Bool {
        switch filter {
        case .all: return true
        case .meals(let meal):
            guard item.kind == .meal else { return false }
            guard let meal else { return true }
            return item.meal == meal
        case .reflections: return item.kind == .reflection
        case .recipeLinked: return item.hasRecipeLink
        }
    }

    /// Sections newest day first; inside a day newest time first, ties broken by id so the order is deterministic.
    /// A blank query matches everything. Matching is case- and diacritic-insensitive on the whole search text.
    static func sections(items: [JournalTimelineItem], filter: JournalTimelineFilter = .all,
                         query: String = "") -> [JournalTimelineSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = items.filter { item in
            guard matches(item, filter: filter) else { return false }
            return q.isEmpty || item.searchText.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let grouped = Dictionary(grouping: kept, by: { $0.dayKey })
        return grouped.keys.sorted(by: >).map { day in
            let ordered = (grouped[day] ?? []).sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
            }
            return JournalTimelineSection(dayKey: day, items: ordered)
        }
    }
}
