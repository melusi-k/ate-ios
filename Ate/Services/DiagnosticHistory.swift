import Foundation

/// Small, on-device rolling history for investigating failures in sideloaded and beta builds.
/// Only typed event categories are accepted: callers cannot accidentally persist recipe text,
/// prompts, account identifiers, URLs, or raw error descriptions.
struct DiagnosticEvent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case appLaunched
        case appForegrounded
        case appBackgrounded
        case storeOpenFailed
        case storeRecovered
        case storeInMemoryFallback
        case saveFailed
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind

    init(kind: Kind, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .appLaunched: "App launched"
        case .appForegrounded: "App became active"
        case .appBackgrounded: "App entered background"
        case .storeOpenFailed: "Local data store failed to open"
        case .storeRecovered: "Local data store recovered"
        case .storeInMemoryFallback: "Temporary in-memory storage used"
        case .saveFailed: "Data save failed after retries"
        }
    }
}

final class DiagnosticHistory {
    static let shared = DiagnosticHistory()
    static let maximumEntries = 200
    static let storageKey = "ate.diagnostic-history.v1"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key: String
    private var cachedEntries: [DiagnosticEvent]

    init(defaults: UserDefaults = .standard, key: String = DiagnosticHistory.storageKey) {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
            cachedEntries = Array(decoded.suffix(Self.maximumEntries))
        } else {
            cachedEntries = []
        }
    }

    var entries: [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries
    }

    func record(_ kind: DiagnosticEvent.Kind, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        cachedEntries.append(DiagnosticEvent(kind: kind, timestamp: date))
        if cachedEntries.count > Self.maximumEntries {
            cachedEntries.removeFirst(cachedEntries.count - Self.maximumEntries)
        }
        persistLocked()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedEntries.removeAll()
        defaults.removeObject(forKey: key)
    }

    /// Contains app/build/platform metadata and typed events only; no user content or device identifier.
    func exportReport(appVersion: String, buildNumber: String, osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString) -> String {
        let snapshot = entries
        let formatter = ISO8601DateFormatter()
        let lines = snapshot.map { "\(formatter.string(from: $0.timestamp))  \($0.kind.rawValue)" }
        return ([
            "Ate diagnostic report",
            "App version: \(appVersion)",
            "Build: \(buildNumber)",
            "OS: \(osVersion)",
            "Events: \(snapshot.count)",
            "",
            "Events are stored on this device. This report contains event categories and timestamps only.",
            "A missing event does not prove that an event did not occur; abrupt termination may prevent recording.",
            "",
            "Timestamp (UTC)  Event"
        ] + lines).joined(separator: "\n")
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(cachedEntries) else { return }
        defaults.set(data, forKey: key)
    }
}
