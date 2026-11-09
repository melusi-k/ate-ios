import Foundation

/// A lightweight recipe pointer shown on an insight, linking a pattern back to the saved
/// recipe that generated it (audit: cooking history must relate to its recipes).
struct RecipeReference: Equatable {
    let id: String
    let title: String
}

/// How prominently the Health tile may present each access state.
/// Audit direction: when Apple Health is not connected, Health stays a quiet, optional
/// setup instead of a dominant warning. Only a connected state owns the full card.
enum InsightsHealthProminence: Equatable {
    /// Connected and loading or loaded: full Health content is appropriate.
    case connected
    /// Not connected yet: a compact optional-setup row with a single Connect action.
    case quietConnect
    /// Unavailable, denied or missing entitlement: a muted notice row, never a takeover.
    case quietNotice
}

/// The tested contract between Health access state and what the Insights screen may show.
struct InsightsHealthPresentation: Equatable {
    let prominence: InsightsHealthProminence
    let showsConnect: Bool
    let showsSettings: Bool
    let showsRetry: Bool

    static func make(access: HealthAccess) -> InsightsHealthPresentation {
        switch access {
        case .requested:
            // HealthKit never tells a read-only app it was denied, so "requested" is the connected path.
            return InsightsHealthPresentation(prominence: .connected, showsConnect: false, showsSettings: false, showsRetry: true)
        case .notDetermined:
            return InsightsHealthPresentation(prominence: .quietConnect, showsConnect: true, showsSettings: false, showsRetry: false)
        case .denied:
            return InsightsHealthPresentation(prominence: .quietNotice, showsConnect: false, showsSettings: true, showsRetry: true)
        case .unavailable, .entitlementMissing:
            return InsightsHealthPresentation(prominence: .quietNotice, showsConnect: false, showsSettings: false, showsRetry: false)
        }
    }
}

/// Sample Health scenarios must be unmistakable: every tile whose content is derived from the
/// active (sample) Health service carries the sample marker, so sample data can never be
/// confused with actual personal data.
enum InsightsSampleMarking {
    /// Tiles rendered from `HealthContext` (state, meal suggestions, reflection prompts).
    static let healthDerivedTileIDs: [String] = ["bodyToday", "suggestedMeals", "dailyReflection"]
    /// The Library "Today" card renders the same Health context; sample truth covers it too.
    static let libraryTodayCardID = "libraryTodayCard"

    static func requiresSampleBadge(tileID: String, isSample: Bool) -> Bool {
        isSample && (tileID == libraryTodayCardID || healthDerivedTileIDs.contains(tileID))
    }
}
