import Foundation

/// Settings copy, kept as pure functions so the wording is unit-testable without
/// booting the UI. Sync truth verified against `AppStore.syncNow` (only `recipe`
/// and `shopping` records sync) and `AteDataArchive` (recipes, shopping items,
/// nutrition diary entries, nutrition goals, app settings, timer preferences).
/// Nutrition, Journal and preferences are local-only. The export archive carries
/// everything except Journal today; Journal portability is separate P1 work, so no
/// Settings copy may claim the Journal is exported.
enum SettingsCopy {
    /// Shown directly under the account card: what syncs and what stays local.
    static func syncSummary(accountAvailable: Bool, signedIn: Bool) -> String {
        if !accountAvailable {
            return "Cloud sync isn't configured in this build. Everything stays on this iPhone."
        }
        if signedIn {
            return "Syncs to your account: recipes and your shopping list. Stays on this iPhone only: food diary, nutrition goals, Journal and app preferences."
        }
        return "Everything is stored on this iPhone. Sign in to sync your recipes and shopping list across devices."
    }

    /// Footer for Your data (Clear all). Signed-out wording is unchanged from the
    /// current app; the signed-in wording is unchanged too, so existing behaviour
    /// descriptions stay stable while the top-of-screen summary adds the detail.
    static func dataFooter(signedIn: Bool) -> String {
        if signedIn {
            return "Recipes and your shopping list sync to your ate account (Supabase, EU). Shared recipes are public to anyone with the link."
        }
        return "Recipes are stored on this iPhone only. Sign in to sync them to your account."
    }

    /// Footer for Nutrition: where diary and goals live.
    static let nutritionFooter = "Your food diary and nutrition goals are stored on this iPhone only. They're included in your data export."

    /// Footer for Tools: what a data export currently contains.
    static let toolsFooter = "A data export includes your recipes, shopping list, food diary, nutrition goals and app preferences."

    /// Shown under AI on this device: availability and device compatibility in plain
    /// terms. Matches `OnDeviceBackend`: Apple Foundation Models on iOS 26+ when the
    /// device supports Apple Intelligence, otherwise the demo (mock) model whose
    /// cards carry the Demo source badge.
    static let aiExplanation = "Recipe generation runs on this iPhone using Apple's on-device model when the device supports Apple Intelligence (iOS 26 or later). Without it, ate uses a demo model so you can still try every flow, and demo cards are marked Demo."
}
