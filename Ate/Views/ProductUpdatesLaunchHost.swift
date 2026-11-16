import SwiftUI
import StoreKit

/// Native, offline launch presentation. Defer to onboarding, recovery and
/// incoming work instead of competing with their existing presentation owners.
struct ProductUpdatesLaunchHost: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var release: ProductRelease?
    @State private var presentedVersion: String?
    private let catalog = ProductUpdatesCatalog.load()
    private let seen = ProductUpdatesSeenStore(defaults: ProductUpdatesSeenStore.launchDefaults)

    private var blocked: Bool {
        store.showOnboarding || store.recovery != nil || store.authSheet != nil ||
        store.cookTarget != nil || store.quickAdd != nil || store.pendingImport != nil ||
        store.cookedReflectionPresentedID != nil || store.cookedReflectionPendingID != nil ||
        store.showNutritionDiary || store.showNutritionDiaryEntry ||
        store.productUpdatesIncomingWork.received || AppConfig.launchURL != nil
    }
    private func presentIfEligible() {
        guard scenePhase == .active, !blocked, release == nil, presentedVersion == nil else { return }
        // Existing hermetic journeys keep their own screens. This opt-in runs
        // the real launch path for its persistence/paging acceptance journey.
        guard !AppConfig.isUITesting || ProcessInfo.processInfo.arguments.contains("-qaReleaseNotesLaunch") else { return }
        if let next = seen.unseenRelease(in: catalog, version: AppConfig.appVersion,
                                        build: Int(AppConfig.buildNumber) ?? 0,
                                        channel: AppConfig.isBetaBuild ? "beta" : "release") {
            store.productUpdatesIncomingWork.tourPresented = true
            presentedVersion = next.version
            release = next
        }
    }
    func body(content: Content) -> some View {
        content
            .task { presentIfEligible() }
            .onChange(of: blocked) { _, _ in presentIfEligible() }
            .onChange(of: store.productUpdatesIncomingWork.received) { _, incoming in
                if incoming { release = nil }
            }
            .onChange(of: scenePhase) { _, _ in presentIfEligible() }
            .sheet(item: $release, onDismiss: {
                let incoming = store.productUpdatesIncomingWork.received
                let pendingURLs = store.productUpdatesIncomingWork.finishTour()
                if !incoming, let version = presentedVersion {
                    seen.markSeen(version)
                    requestReview() // StoreKit decides whether a prompt is appropriate.
                }
                for url in pendingURLs { store.handle(url: url) }
            }) { ProductWhatsNewView(release: $0) }
    }
}
