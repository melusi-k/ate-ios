import Foundation

/// App Group shared between the app and the widget extension.
/// Free-Apple-ID sideloads may not get the group; then we fall back to standard UserDefaults (app-only).
enum SharedContainer {
    /// Resolved at runtime (sideloaders may rename the group); see AppGroupResolver.
    static var groupID: String { AppGroupResolver.current.id }
    static var isAvailable: Bool { AppGroupResolver.current.available }
    static var defaults: UserDefaults {
        if isAvailable, let d = UserDefaults(suiteName: groupID) { return d }
        return .standard
    }
}

/// Persisted snapshot of a cook timer (restored after relaunch; readable by the widget).
struct TimerSnapshot: Codable, Equatable {
    var recipeID: String
    var recipeTitle: String
    var stepIndex: Int
    var stepCount: Int
    var stepText: String
    var total: Int
    var endDate: Date?
    var pausedRemaining: Int

    static let key = "ate.timers.v1"
    static func load() -> [TimerSnapshot] {
        SharedContainer.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([TimerSnapshot].self, from: $0) } ?? []
    }
    static func save(_ s: [TimerSnapshot]) {
        SharedContainer.defaults.set(try? JSONEncoder().encode(s), forKey: key)
    }
}
