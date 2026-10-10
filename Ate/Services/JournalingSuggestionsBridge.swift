import SwiftUI
#if canImport(JournalingSuggestions) && !targetEnvironment(simulator)
import JournalingSuggestions
#endif

/// Apple's Journaling Suggestions picker: READS a moment the user chooses (photo, workout, place…) from the
/// system's suggestions into Ate. It does not put anything into Apple's Journal app.
/// Needs com.apple.developer.journal.allow, which only paid Apple Developer Program teams can provision,
/// so the picker is hidden unless the installed profile carries that entitlement.
enum JournalingSuggestionsGate {
    /// Settings toggle (OFF by default; only switchable when the entitlement is present).
    static let settingKey = "ate.journalingSuggestions.enabled"
    static var isAvailable: Bool {
        #if canImport(JournalingSuggestions) && !targetEnvironment(simulator)
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1) else { return false }
        return raw.contains("com.apple.developer.journal.allow")
        #else
        return false
        #endif
    }
}

/// What Ate keeps from a picked suggestion.
struct PickedMoment: Equatable {
    var title: String
    var date: Date?
    var photoURLs: [URL]
    var isWorkout: Bool
}

struct JournalingSuggestionsButton: View {
    let onPick: (PickedMoment) -> Void
    var body: some View {
        #if canImport(JournalingSuggestions) && !targetEnvironment(simulator)
        if JournalingSuggestionsGate.isAvailable {
            JournalingSuggestionsPicker {
                Label("Pick a moment from Journaling Suggestions", systemImage: "book.pages")
                    .font(AteFont.body(15, .semibold))
            } onCompletion: { s in
                let photos = await s.content(forType: JournalingSuggestion.Photo.self).map(\.photo)
                let workouts = await s.content(forType: JournalingSuggestion.Workout.self)
                onPick(PickedMoment(title: s.title, date: s.date?.start, photoURLs: photos, isWorkout: !workouts.isEmpty))
            }
            .accessibilityIdentifier("insights.journalingPicker")
        }
        #endif
    }
}
