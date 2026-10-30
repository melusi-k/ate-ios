import Foundation

/// A stable, local-only lifecycle for evidence-backed insights.
/// Only a one-way fingerprint is persisted; recipe titles and underlying data are not.
enum InsightLifecycleStatus: String, Codable, Equatable {
    case active
    case seen
    case dismissed
    case snoozed
    case resolved
    case expired
}

struct InsightLifecycleRecord: Codable, Equatable {
    var status: InsightLifecycleStatus
    var evidenceFingerprint: String
    var updatedAt: Date
    var snoozedUntil: Date?
}

struct InsightLifecycleStore {
    static let shared = InsightLifecycleStore()

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "insights.lifecycle.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func record(for id: String) -> InsightLifecycleRecord? {
        records()[id]
    }

    /// Returns true only while this exact evidence version is eligible to be shown.
    /// A changed evidence fingerprint starts a new active version.
    @discardableResult
    func shouldPresent(id: String, evidenceFingerprint: String, now: Date = Date()) -> Bool {
        guard !id.isEmpty, !evidenceFingerprint.isEmpty else { return false }
        var all = records()
        if let existing = all[id], existing.evidenceFingerprint == evidenceFingerprint {
            if existing.status == .snoozed, let until = existing.snoozedUntil, until <= now {
                all[id] = InsightLifecycleRecord(status: .active, evidenceFingerprint: evidenceFingerprint, updatedAt: now, snoozedUntil: nil)
                save(all)
                return true
            }
            return existing.status == .active
        }
        all[id] = InsightLifecycleRecord(status: .active, evidenceFingerprint: evidenceFingerprint, updatedAt: now, snoozedUntil: nil)
        save(all)
        return true
    }

    func markSeen(_ id: String, now: Date = Date()) {
        transition(id, to: .seen, now: now)
    }

    func dismiss(_ id: String, now: Date = Date()) {
        transition(id, to: .dismissed, now: now)
    }

    func resolve(_ id: String, now: Date = Date()) {
        transition(id, to: .resolved, now: now)
    }

    func expire(_ id: String, now: Date = Date()) {
        transition(id, to: .expired, now: now)
    }

    func snooze(_ id: String, until: Date, now: Date = Date()) {
        guard var allRecord = records()[id] else { return }
        allRecord.status = .snoozed
        allRecord.updatedAt = now
        allRecord.snoozedUntil = max(now, until)
        var all = records()
        all[id] = allRecord
        save(all)
    }

    func reset(_ id: String) {
        var all = records()
        all.removeValue(forKey: id)
        save(all)
    }

    private func transition(_ id: String, to status: InsightLifecycleStatus, now: Date) {
        var all = records()
        guard var record = all[id] else { return }
        record.status = status
        record.updatedAt = now
        record.snoozedUntil = nil
        all[id] = record
        save(all)
    }

    private func records() -> [String: InsightLifecycleRecord] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: InsightLifecycleRecord].self, from: data) else { return [:] }
        return decoded
    }

    private func save(_ records: [String: InsightLifecycleRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// Fingerprints the factual inputs, not generated wording, so paraphrasing cannot make an old insight look new.
enum RecipeProgressInsightFingerprint {
    static func make(_ input: RecipeProgressInsightInput) -> String {
        let duplicateGroups = input.duplicateTitleGroups
            .map { $0.map(normalize).sorted().joined(separator: ",") }
            .sorted()
            .joined(separator: ";")
        let fields = [
            String(input.savedRecipeCount),
            String(input.cookedRecipeCount),
            String(input.cookingDayCount),
            normalize(input.mostCookedRecipe ?? ""),
            String(input.recordedMealsThisWeek),
            String(input.firstTimeRecipesThisWeek),
            String(input.currentStreak),
            input.recipeTitles.map(normalize).sorted().joined(separator: ","),
            duplicateGroups
        ]
        let bytes = fields.joined(separator: "|").utf8
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
