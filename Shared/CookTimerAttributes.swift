import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shared between the app and the AteWidgets extension.
struct CookTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stepIndex: Int        // 0-based
        var stepCount: Int
        var stepText: String
        var startDate: Date       // countdown interval start (for Text(timerInterval:))
        var endDate: Date?        // nil when paused
        var remaining: Int        // seconds left (authoritative when paused)
        var total: Int
        var finished: Bool = false
    }
    var recipeID: String
    var recipeTitle: String
    var timerID: String
}
#endif
