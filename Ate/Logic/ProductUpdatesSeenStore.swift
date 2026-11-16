import Foundation

/// Local presentation state only. Build changes within one marketing version do
/// not show the same release again. Selection never invents a missing version.
struct ProductUpdatesSeenStore {
    static var launchDefaults: UserDefaults {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if AppConfig.isUITesting, let index = args.firstIndex(of: "-qaReleaseNotesDefaults"),
           args.indices.contains(index + 1), let suite = UserDefaults(suiteName: args[index + 1]) { return suite }
        #endif
        return .standard
    }
    private let defaults: UserDefaults
    private let key = "productUpdates.seenVersions.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func hasSeen(_ version: String) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(version)
    }
    func markSeen(_ version: String) {
        guard !version.isEmpty else { return }
        let versions = Set(defaults.stringArray(forKey: key) ?? []).union([version])
        defaults.set(versions.sorted(), forKey: key)
    }
    func unseenRelease(in catalog: ProductUpdatesCatalog?, version: String,
                       build: Int, channel: String) -> ProductRelease? {
        guard !version.isEmpty, !hasSeen(version) else { return nil }
        return catalog?.visibleReleases(build: build, channel: channel)
            .first { $0.version == version && !$0.slides.isEmpty }
    }
}
