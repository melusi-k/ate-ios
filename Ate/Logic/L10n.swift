import Foundation

/// Typed keys into Localizable.xcstrings (English source; add languages in Xcode's String Catalog editor).
/// SwiftUI `Text("literal")` strings are also extracted into the catalog on build (SWIFT_EMIT_LOC_STRINGS).
enum L10n {
    static var libraryTitle: String { String(localized: "library.title", defaultValue: "Your kitchen library") }
    static var libraryEmptyTitle: String { String(localized: "library.empty.title", defaultValue: "Nothing saved yet") }
    static var libraryEmptyMessage: String { String(localized: "library.empty.message", defaultValue: "Paste a link or a screenshot and get a clean recipe card in seconds.") }
    static var libraryAdd: String { String(localized: "library.add", defaultValue: "Add recipe") }
    static var shoppingTitle: String { String(localized: "shopping.title", defaultValue: "Shopping list") }
    static var settingsTitle: String { String(localized: "settings.title", defaultValue: "Settings") }
    static var offlineBanner: String { String(localized: "offline.banner", defaultValue: "You're offline — recipes, cook mode and your list still work.") }
    static var retry: String { String(localized: "common.retry", defaultValue: "Try again") }
    static var voiceListening: String { String(localized: "voice.listening", defaultValue: "Listening for “next”, “back”, “start timer” or “repeat”") }
    static var cookNext: String { String(localized: "cook.next", defaultValue: "Next") }
    static var cookBack: String { String(localized: "cook.back", defaultValue: "Back") }
}
