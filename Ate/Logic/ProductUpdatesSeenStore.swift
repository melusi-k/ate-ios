import Foundation

/// Local presentation state only. Records tour dismissal from the Settings
/// release-notes surface; no launch auto-presentation reads it.
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
    func markSeen(_ version: String) {
        guard !version.isEmpty else { return }
        let versions = Set(defaults.stringArray(forKey: key) ?? []).union([version])
        defaults.set(versions.sorted(), forKey: key)
    }
}
