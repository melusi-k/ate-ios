import SwiftUI

/// Mounts no ordinary view, timer, watch bridge, intent relay or store environment
/// until the startup owner returns its admitted graph. Failure never looks empty.
@MainActor
struct JournalStartupGateView<Graph, Ready: View>: View {
    let startup: ResetAwareStartup<Graph>
    let ready: (Graph) -> Ready

    var body: some View {
        Group {
            switch startup.state {
            case .notStarted, .checkingReset:
                ProgressView("Checking saved data...")
                    .accessibilityIdentifier("journal.startup.checking")
            case .ready(let graph):
                ready(graph)
            case .blocked(let reason):
                blocked(reason)
            case .failed(let message):
                ContentUnavailableView("Saved data is not ready", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(message))
                    .accessibilityIdentifier("journal.startup.failed")
            }
        }
        .task { await startup.start() }
    }

    private func blocked(_ reason: AppStore.ClearAllState) -> some View {
        let detail: String
        switch reason {
        case .unavailable(let message): detail = message
        case .serverOutcomeUnverified:
            detail = "An earlier account-data request has not been verified. Ate is keeping saved data closed until its outcome can be checked."
        case .cloudCommittedLocalIncomplete:
            detail = "The account-data request completed online, but local cleanup still needs verification. Saved data has not been reopened."
        case .completed:
            detail = "Saved data is waiting for safe startup."
        }
        return ContentUnavailableView("Saved data is not ready", systemImage: "externaldrive.badge.exclamationmark",
            description: Text(detail))
            .accessibilityIdentifier("journal.startup.blocked")
    }
}
