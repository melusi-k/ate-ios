import Foundation
import CryptoKit

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

    init(defaults: UserDefaults = .standard, storageKey: String? = nil, accountID: String? = nil) {
        self.defaults = defaults
        if let storageKey {
            self.storageKey = storageKey
        } else if let accountID, !accountID.isEmpty {
            let digest = SHA256.hash(data: Data(accountID.utf8))
            let scope = digest.map { String(format: "%02x", $0) }.joined()
            self.storageKey = "insights.lifecycle.v1.account.\(scope)"
        } else {
            self.storageKey = "insights.lifecycle.v1"
        }
    }

    /// Removes all persisted insight lifecycle metadata when the user explicitly wipes local data.
    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
        where key == "insights.lifecycle.v1" || key.hasPrefix("insights.lifecycle.v1.account.") {
            defaults.removeObject(forKey: key)
        }
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

    /// Marks an insight seen only if its evidence still matches what the user acted on.
    @discardableResult
    func markSeen(id: String, evidenceFingerprint: String, now: Date = Date()) -> Bool {
        transition(id, to: .seen, expectedFingerprint: evidenceFingerprint, now: now)
    }

    func dismiss(_ id: String, now: Date = Date()) {
        transition(id, to: .dismissed, now: now)
    }

    @discardableResult
    func dismiss(id: String, evidenceFingerprint: String, now: Date = Date()) -> Bool {
        transition(id, to: .dismissed, expectedFingerprint: evidenceFingerprint, now: now)
    }

    func resolve(_ id: String, now: Date = Date()) {
        transition(id, to: .resolved, now: now)
    }

    func expire(_ id: String, now: Date = Date()) {
        transition(id, to: .expired, now: now)
    }

    func snooze(_ id: String, until: Date, now: Date = Date()) {
        guard let record = records()[id] else { return }
        _ = snooze(id: id, evidenceFingerprint: record.evidenceFingerprint, until: until, now: now)
    }

    @discardableResult
    func snooze(id: String, evidenceFingerprint: String, until: Date, now: Date = Date()) -> Bool {
        var all = records()
        guard var record = all[id], record.evidenceFingerprint == evidenceFingerprint else { return false }
        record.status = .snoozed
        record.updatedAt = now
        record.snoozedUntil = max(now, until)
        all[id] = record
        save(all)
        return true
    }

    func reset(_ id: String) {
        var all = records()
        all.removeValue(forKey: id)
        save(all)
    }

    @discardableResult
    private func transition(_ id: String, to status: InsightLifecycleStatus, expectedFingerprint: String? = nil, now: Date) -> Bool {
        var all = records()
        guard var record = all[id],
              expectedFingerprint == nil || record.evidenceFingerprint == expectedFingerprint else { return false }
        record.status = status
        record.updatedAt = now
        record.snoozedUntil = nil
        all[id] = record
        save(all)
        return true
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
        let digest = SHA256.hash(data: Data(fields.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
