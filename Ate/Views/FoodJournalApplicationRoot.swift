import SwiftUI

/// Production application root. The old graph is removed before its asynchronous
/// drain completes. No normal UI exists in checking/blocked states.
@MainActor
struct FoodJournalApplicationRoot: View {
    @State private var owner = FoodJournalApplicationOwner()
    var body: some View {
        Group {
            switch owner.state {
            case .checking:
                ProgressView("Checking saved data...")
                    .accessibilityIdentifier("journal.startup.checking")
            case .blocked(let message):
                ContentUnavailableView("Saved data is not ready", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message))
                    .accessibilityIdentifier("journal.startup.blocked")
            case .ready(let id, let store):
                RootView()
                    .environment(store)
                    .preferredColorScheme(store.settings.appearance.preferredColorScheme)
                    .id(id)
                    .onAppear { owner.mounted(id) }
                    .onDisappear { owner.unmounted(id) }
            }
        }
        .task { await owner.start() }
        .onOpenURL { owner.handle($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { owner.handle(url) }
        }
    }
}
