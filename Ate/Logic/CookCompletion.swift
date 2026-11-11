import Foundation

/// What the Journal needs to know about an explicitly finished cook (#245). The Finish button is the only source:
/// opening Cook Mode or reaching the last step is never a completion, and nothing here logs eaten food.
/// This type only describes the event. Canonical Journal writes belong to the Journal integration, which must
/// treat `id` as the stable key: delivery is at-least-once, so the same event can arrive again.
struct CookCompletionEvent: Codable, Equatable, Identifiable {
    /// "cook-" plus the persistent `CookSession.sessionID`, so every delivery and a Finish repeated after a crash
    /// carry the same id, and a later cook has a new session and a new id. Not derived from a timestamp.
    let id: String
    let recipeID: String
    /// Title captured at Finish so the entry stays understandable after the recipe is edited or deleted.
    let recipeTitle: String
    /// Local YYYY-MM-DD in the `CookingHistory.key(for:)` format.
    let cookedDayKey: String
    let completedAt: Date

    init(recipeID: String, recipeTitle: String, completedAt: Date, dayKey: String, id: String = "cook-" + UUID().uuidString) {
        self.id = id
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.completedAt = completedAt
        self.cookedDayKey = dayKey
    }

    /// The durable recipe link for a Journal reflection about this cook.
    var recipeSnapshot: JournalRecipeSnapshot {
        JournalRecipeSnapshot(recipeID: recipeID, title: recipeTitle, cookedDayKey: cookedDayKey)
    }
}

/// Why the outbox refused to change.
enum CookCompletionOutboxError: Error, Equatable {
    /// A value is stored under the key but cannot be decoded. It is left byte-for-byte as found.
    case unreadable
    /// Existing cooking-history bytes cannot be decoded; do not offer to set aside the unrelated outbox.
    case historyUnreadable
    case encodeFailed
    /// The event to queue has an empty id. Refused before any write.
    case invalidEvent
    /// The write did not read back as intended. This is a read-back check, not crash-proof durability.
    case verifyFailed
    /// The cook session could not be verified or cleared. Earlier finish steps may already be saved.
    case session
}

/// Durable list of finished cooks the Journal has not acknowledged yet. A Finish is queued here BEFORE anything
/// else, so the completed event survives a missing consumer, a suppressed or dismissed reflection offer, and a
/// relaunch. Delivery is at-least-once with a stable id: the consumer dedupes by `id` and calls `acknowledge`.
/// This is not an exactly-once guarantee. Nothing consumes it until the Journal integration binds a drain.
/// An absent value is an empty list. A stored value that cannot be read is NOT empty (there is no non-throwing list: use `load()`): every change throws and
/// leaves the stored bytes untouched until `setUnreadableAside()` copies them to a separate key.
final class CookCompletionOutbox {
    static let defaultsKey = "ate.cook.completionOutbox.v1"
    static let unreadableKeyPrefix = "ate.cook.completionOutbox.v1.unreadable."
    private let writerBoundary: FoodJournalWriterBoundary
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, writerBoundary: FoodJournalWriterBoundary = .legacy) {
        self.defaults = defaults
        self.writerBoundary = writerBoundary
    }

    /// Throws `.unreadable` when something is stored that cannot be decoded; returns [] only when nothing is stored.
    func load() throws -> [CookCompletionEvent] {
        guard let raw = defaults.object(forKey: Self.defaultsKey) else { return [] }
        guard let data = raw as? Data, let events = try? JSONDecoder().decode([CookCompletionEvent].self, from: data) else {
            throw CookCompletionOutboxError.unreadable
        }
        // Empty or repeated ids break the one-event-per-id contract: treat as unreadable and keep the bytes.
        guard !events.contains(where: { $0.id.isEmpty }), Set(events.map(\.id)).count == events.count else {
            throw CookCompletionOutboxError.unreadable
        }
        return events
    }

    /// Idempotent by id and returns the event STORED under that id. A retry with the same id but a different date,
    /// title or day gets the first-stored event back, so every consumer sees one payload per id. Encodes before
    /// writing, then reads back and compares the whole queued array; throws without a silent change otherwise.
    @discardableResult
    func enqueue(_ event: CookCompletionEvent) throws -> CookCompletionEvent {
        return try writerBoundary.withEffect {
            guard !event.id.isEmpty else { throw CookCompletionOutboxError.invalidEvent }
            let events = try load()
            if let stored = events.first(where: { $0.id == event.id }) { return stored }
            try write(events + [event])
            return event

        }
    }

    func acknowledge(id: String) throws {
        return try writerBoundary.withEffect {
            let events = try load()
            let kept = events.filter { $0.id != id }
            guard kept.count != events.count else { return }
            try write(kept)

        }
    }

    /// Copies the unreadable bytes to a fresh key, verifies the copy, and only then clears the main key.
    /// Returns the key that holds the original bytes. Does nothing when the store is readable.
    @discardableResult
    func setUnreadableAside() throws -> String? {
        return try writerBoundary.withEffect {
            do { _ = try load(); return nil } catch CookCompletionOutboxError.unreadable {}
            guard let raw = defaults.object(forKey: Self.defaultsKey) else { return nil }
            let key = Self.unreadableKeyPrefix + UUID().uuidString
            defaults.set(raw, forKey: key)
            guard let copy = defaults.object(forKey: key), (copy as? NSObject)?.isEqual(raw) == true else {
                defaults.removeObject(forKey: key)
                throw CookCompletionOutboxError.verifyFailed
            }
            defaults.removeObject(forKey: Self.defaultsKey)
            guard defaults.object(forKey: Self.defaultsKey) == nil else { throw CookCompletionOutboxError.verifyFailed }
            return key

        }
    }

    private func write(_ events: [CookCompletionEvent]) throws {
        let data: Data
        do { data = try JSONEncoder().encode(events) } catch { throw CookCompletionOutboxError.encodeFailed }
        defaults.set(data, forKey: Self.defaultsKey)
        guard let back = try? load(), back == events else { throw CookCompletionOutboxError.verifyFailed }
    }
}

/// Frequency for the optional post-cook reflection offer. This is a routine product choice the owner delegated
/// ("make the best decisions based on the docs and what is best practice", Nov 3 phonemsg-01M6H1PY83YGVKZ1A1WGXWTAS4)
/// and the completion-sheet proposal accepted Nov 7 includes at most one highlighted nudge per day.
/// The rule: at most one offer per local day, counted when the offer is actually shown, however the
/// user answers it. An offer that never reached the screen does not use up the day. Cooking completion never
/// depends on this policy.
final class CookReflectionOfferPolicy {
    static let defaultsKey = "ate.cook.reflectionOffer.v1"
    private let calendar: Calendar
    private let writerBoundary: FoodJournalWriterBoundary
    private let defaults: UserDefaults

    init(calendar: Calendar = .autoupdatingCurrent, defaults: UserDefaults = .standard,
         writerBoundary: FoodJournalWriterBoundary = .legacy) {
        self.writerBoundary = writerBoundary
        self.calendar = calendar
        self.defaults = defaults
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// True when no offer has been shown yet on the local day of `date`.
    func shouldOffer(on date: Date) -> Bool {
        defaults.string(forKey: Self.defaultsKey) != dayKey(date)
    }

    /// Call when the invitation is on screen, not when it is decided.
    func markShown(on date: Date) {
        _ = try? writerBoundary.withEffect {
            defaults.set(dayKey(date), forKey: Self.defaultsKey)

        }
    }
}

/// One Finish per Cook Mode view. After it begins, nothing in the view may write the cook session again, so
/// onAppear or a step change cannot recreate the session that Finish just cleared. This is view-lifetime state,
/// not a durable once-only guarantee: cooking the recipe again later starts a new session and a new event.
struct CookFinishState: Equatable {
    private(set) var isFinished = false
    var allowsSessionWrites: Bool { !isFinished }

    /// True for the first call only.
    mutating func begin() -> Bool {
        guard !isFinished else { return false }
        isFinished = true
        return true
    }
}

/// Composer text for "Write a note" after a cook. Never replaces a draft the user already has.
enum CookReflectionDraft {
    static func prefill(existing: String, recipeTitle: String) -> String {
        existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cooked \(recipeTitle). " : existing
    }
}

/// Where Cook Mode resumes after the user leaves and returns, and what happens to a session that can no
/// longer be resumed.
enum CookSessionRecovery {
    /// A running timer's step wins (the user is mid-wait there); otherwise the saved step. The result is always a
    /// valid index, so a recipe that lost steps since the session was saved never resumes past its end.
    /// `stepCount <= 0` has no valid step and returns 0.
    static func resumeStep(savedStep: Int?, runningTimerStep: Int?, stepCount: Int) -> Int {
        guard stepCount > 0 else { return 0 }
        let wanted = runningTimerStep ?? savedStep ?? 0
        return min(max(0, wanted), stepCount - 1)
    }

    enum Reconciliation: Equatable {
        /// Keep the session, with its step clamped into the recipe's current steps.
        case keep(stepIndex: Int)
        /// The recipe is gone or has no steps, so the resume control would show nothing and never leave.
        case discard
    }

    /// `stepCount` is nil when the recipe no longer exists.
    static func reconcile(session: CookSession, stepCount: Int?) -> Reconciliation {
        guard let stepCount, stepCount > 0 else { return .discard }
        return .keep(stepIndex: min(max(0, session.stepIndex), stepCount - 1))
    }
}
