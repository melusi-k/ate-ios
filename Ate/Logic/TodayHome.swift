import Foundation

/// Who presents the store-wide quick-add / share-extension import sheet (#642).
enum HomeSheetOwner: Equatable { case today, collection, none }

/// Pure Today-tab decisions (#642): the greeting and which saved recipes lead the
/// tab. No clocks, stores or backends leak in, so the native tests pin the exact
/// boundaries without a simulator.
enum TodayHome {
    /// Time-of-day greeting for the header, bucketed on the device's local hour
    /// (the view passes Calendar.current's hour). The app does not know the cook's
    /// name, so the greeting never invents one, and the late-night hours stay
    /// neutral instead of claiming an evening that ended hours ago (#645).
    static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    /// Up to `limit` saved recipes leading "What shall we cook?": favourites first,
    /// then the newest additions. Ties break on identity so the order never shuffles
    /// between launches.
    static func preview(_ recipes: [RecipeCard], limit: Int = 3) -> [RecipeCard] {
        guard limit > 0 else { return [] }
        let ordered = recipes.sorted { lhs, rhs in
            if lhs.favorite != rhs.favorite { return lhs.favorite }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id < rhs.id
        }
        return Array(ordered.prefix(limit))
    }

    /// The one canonical collection location inside the Today stack (#642): explicit
    /// collection selection resolves here instead of appending onto detail paths, so
    /// a re-selection from [.library, .recipe] can never stack a second collection.
    static func canonicalCollectionPath() -> [Route] { [.library] }

    /// Exactly one owner for the store-wide quick-add and share-extension import
    /// sheets: Today at the home root, the pushed collection while it is on the
    /// home stack, nobody on other tabs or deeper routes. One owner means one
    /// presentation and one save.
    static func sheetOwner(isHomeTab: Bool, path: [Route]) -> HomeSheetOwner {
        guard isHomeTab else { return .none }
        if path.isEmpty { return .today }
        return path.last == .library ? .collection : .none
    }

    /// The pushed collection keeps tab-root chrome (bottom accessory, timer home)
    /// only at its canonical root, never on a duplicate stacked above a detail.
    static func isCollectionRoot(isHomeTab: Bool, path: [Route]) -> Bool {
        isHomeTab && path == canonicalCollectionPath()
    }
}
