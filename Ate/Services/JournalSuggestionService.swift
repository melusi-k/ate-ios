import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reflective prompts for "Reflect on your day". Apple Intelligence when available, templates otherwise.
/// This feeds Ate's own journal; it does not (and cannot) write to Apple's Journal app.
enum JournalSuggestionService {
    static func templates(for insight: HealthInsight) -> [JournalPrompt] {
        let t: [String]
        switch insight.state {
        case .recovery: t = ["How did your body feel after that workout? What would help you recover tonight?",
                             "Which meal today gave you the most energy back?"]
        case .lowEnergy: t = ["You had a short night. What would make this evening feel easy and nourishing?",
                              "What is one comforting dish you'd love to cook this week?"]
        case .performance: t = ["You've got energy today. What could you cook ahead to make the week easier?",
                                "What made today feel good, and how can you repeat it?"]
        case .underactive: t = ["It's been a quieter week. Want to plan a lighter dinner and a 10-minute walk?",
                                "What got in the way of moving more, and what's one small change for tomorrow?"]
        case .balanced: t = ["What did you enjoy eating today?", "Is there a dish you want to try cooking this week?"]
        }
        return t.map { JournalPrompt(text: $0, state: insight.state) }
    }

    static func prompts(for insight: HealthInsight, useModel: Bool = OnDeviceBackend.isModelAvailable && !AppConfig.isUITesting) async -> [JournalPrompt] {
        let base = templates(for: insight)
        guard useModel else { return base }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
            You write one short, warm, non-judgemental journaling question for a cooking app. No medical advice, \
            no numbers about weight or calories, under 25 words, end with a question mark.
            """)
            let ask = "Today: \(insight.headline) State: \(insight.state.title). Write the question."
            if let r = try? await session.respond(to: ask) {
                let text = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.isAcceptable(text) { return [JournalPrompt(text: text, state: insight.state, generated: true)] + base.prefix(1) }
            }
        }
        #endif
        return base
    }

    /// Acceptance gate for a generated reflection. The instruction says under 25 words ending in a
    /// question mark, so the check enforces both now (the old 8-220 character check let long
    /// non-questions through). A rejection just falls back to the templates.
    static func isAcceptable(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = t.split { $0.isWhitespace }.count
        return t.count > 8 && t.count < 220 && words < 25 && t.hasSuffix("?")
    }
}

/// How the journal store opened (#245 phase 3). The timeline presents anything but `.ok`
/// honestly: a recovered-empty journal is never silently shown as the user's actual history.
enum JournalOpenState: Equatable {
    case ok
    case recovered(backupName: String?)
    case inMemoryFallback(error: String?)
    case unavailable(error: String?)
}

/// Local SwiftData store for Ate journal entries (in-memory during UI tests). Never synced.
/// The container schema also holds Food Journal meal payloads (#245). The open path mirrors the
/// recipe store's corruption recovery (R-DATA-01): a damaged store is moved aside with its
/// -wal/-shm sidecars before a fresh one opens, and `openState` carries what happened so the
/// timeline can say it. Journal media (Application Support/JournalMedia) lives outside the
/// store files and is never touched by recovery.
@MainActor
final class JournalStore {
    static let shared = JournalStore()
    private let writerBoundary: FoodJournalWriterBoundary
    private var writeReflectionContext: (ModelContext) throws -> Void = { try $0.save() }
    let container: ModelContainer?
    private(set) var openState: JournalOpenState
    convenience init(inMemory: Bool = AppConfig.isUITesting,
                     writerBoundary: FoodJournalWriterBoundary = .legacy) {
        let opened: (ModelContainer?, JournalOpenState)
        do {
            opened = try writerBoundary.withEffect {
                if inMemory {
                    let container = try? ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                        configurations: ModelConfiguration("AteJournal", isStoredInMemoryOnly: true))
                    let state: JournalOpenState = container == nil ? .unavailable(error: "the in-memory journal failed to open") : .ok
                    return (container, Self.qaForcedOpenState() ?? state)
                }
                // Preserve the existing named-store path. Recovery may move bytes and
                // therefore belongs inside admission, before any ordinary consumers.
                let outcome = StoreRecovery.open(url: ModelConfiguration("AteJournal").url) { cfg in
                    try ModelContainer(for: JournalEntry.self, JournalMealPayload.self, configurations: cfg)
                }
                return (outcome.container, Self.openState(for: outcome))
            }
        } catch {
            opened = (nil, .unavailable(error: "safe Journal startup could not be verified"))
        }
        self.init(container: opened.0, openState: opened.1, writerBoundary: writerBoundary)
        do {
            try writerBoundary.withEffect {
                container?.mainContext.autosaveEnabled = false
                seedMomentEntryForUITests()
                try removeImagePromptEntriesOnce()
            }
        } catch {
            openState = .unavailable(error: "Journal startup maintenance could not be verified")
        }
    }

    /// Explicit container injection for storage tests; production uses the verified open path above.
    init(container: ModelContainer?, openState: JournalOpenState,
         writerBoundary: FoodJournalWriterBoundary = .legacy,
         writeReflectionContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.writerBoundary = writerBoundary
        self.container = container
        self.openState = openState
        self.writeReflectionContext = writeReflectionContext
    }

    /// UI-test hook (`-qaJournalOpenState <recovered|fallback|unavailable>`): the open state the
    /// timeline must present. Parsing is a pure function so the argument handling itself is testable.
    static func qaForcedOpenState(args: [String] = ProcessInfo.processInfo.arguments) -> JournalOpenState? {
        guard AppConfig.isUITesting, let i = args.firstIndex(of: "-qaJournalOpenState"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "recovered": return .recovered(backupName: "ate-20250101-120000.store")
        case "fallback": return .inMemoryFallback(error: "simulated for UI testing")
        case "unavailable": return .unavailable(error: "simulated for UI testing")
        default: return nil
        }
    }

    /// Maps a recovery outcome to the presented state. Kept separate for unit tests.
    static func openState(for outcome: StoreRecovery.Outcome) -> JournalOpenState {
        if outcome.recovered { return .recovered(backupName: outcome.backupURL?.lastPathComponent) }
        if outcome.inMemoryFallback { return .inMemoryFallback(error: outcome.error) }
        if outcome.container == nil { return .unavailable(error: outcome.error) }
        return .ok
    }
    /// One-time cleanup (b81): earlier builds saved image-generation prompts routed through the journal schema as entries.
    private func removeImagePromptEntriesOnce() throws {
        let k = "ate.journal.imagePromptCleanup.v1"
        guard !UserDefaults.standard.bool(forKey: k), let ctx = container?.mainContext else { return }
        for e in entries() where e.source != .journalMoment && JournalTextGuard.looksLikeImagePrompt(e.text) { ctx.delete(e) }
        try writeReflectionContext(ctx)
        UserDefaults.standard.set(true, forKey: k)
    }
    /// Throwing single-entry read for the detail screen: nil means the entry is genuinely gone,
    /// while a store or fetch failure throws, so the detail shows an error instead of a false
    /// "It may have been deleted".
    func readEntry(_ id: String) throws -> JournalEntry? {
        try readEntries().first { $0.id == id && $0.kindRaw == JournalEntryKind.reflection.rawValue }
    }
    /// Non-throwing read kept for Siri/Shortcuts queries, which have no error surface: a failed
    /// read answers as little as possible rather than throwing through an intent. User-facing
    /// lists use `readEntries()` so a read failure is never shown as an empty journal.
    func entries() -> [JournalEntry] {
        (try? readEntries()) ?? []
    }
    /// Throwing read for user-facing lists. An unopened store or a failed fetch throws, so the
    /// Journal screens show an explicit error with retry instead of "No journal entries yet".
    func readEntries() throws -> [JournalEntry] {
        guard let context = container?.mainContext else { throw JournalReadError.storeUnavailable }
        let rows: [JournalEntry]
        do { rows = try context.fetch(FetchDescriptor<JournalEntry>()) }
        catch { throw JournalReadError.readFailed }
        // MainActor-local comparison avoids a non-Sendable SortDescriptor key path.
        return rows.sorted { $0.createdAt > $1.createdAt }
    }
    @discardableResult
    func save(prompt: String, text: String, state: HealthState?, recipeIDs: [String], momentTitle: String? = nil, momentDate: Date? = nil) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let entry = JournalEntry(prompt: prompt, text: text, state: state, recipeIDs: recipeIDs,
                                 journalingSuggestionTitle: momentTitle, momentDate: momentDate,
                                 source: momentTitle == nil ? .ate : .journalMoment)
        return (try? persistReflection(entry)) != nil
    }
    /// Standalone reflections do not depend on Health or borrow an inferred state.
    /// A separate context keeps unrelated, unsaved main-context edits out of this transaction.
    @discardableResult
    func saveManual(text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManualJournalSaveError.empty }
        let entry = JournalEntry(prompt: "", text: trimmed, state: nil)
        return try persistReflection(entry)
    }

    /// Save only this insertion, never unrelated pending edits in the shared main context.
    private func persistReflection(_ entry: JournalEntry) throws -> String {
        return try writerBoundary.withEffect {
            // Matches the accepted save behaviour: only .unavailable refuses. The in-memory fallback still
            // saves for this session; JournalOpenStateBanner keeps telling the user it is temporary.
            switch openState {
            case .ok, .recovered, .inMemoryFallback: break
            case .unavailable: throw ManualJournalSaveError.unavailable
            }
            guard let container else { throw ManualJournalSaveError.unavailable }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(entry)
            do { try writeReflectionContext(context) }
            catch {
                // Only this short-lived context owns the insertion. Never roll back mainContext.
                context.rollback()
                throw ManualJournalSaveError.failed
            }
            return entry.id

        }
    }

    /// UI tests (`-qaJournalMomentEntry`): one entry that came from a Journal moment, to check the context row.
    func seedMomentEntryForUITests() {
        guard AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaJournalMomentEntry"), entries().isEmpty else { return }
        if case let .journalEntry(p, title, date, state) = JournalingMomentMapper.map(title: "Dinner at Mama's", date: DateInterval(start: Date(timeIntervalSince1970: 1_791_000_000), duration: 3600), hasPhotos: false, isWorkout: false) {
            save(prompt: p, text: "Seeded from a Journal moment", state: state, recipeIDs: [], momentTitle: title, momentDate: date)
        }
    }
    func delete(_ entry: JournalEntry) {
        _ = try? writerBoundary.withEffect {
            guard entry.kindRaw == JournalEntryKind.reflection.rawValue, let container else { return }
            let id = entry.id
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            guard let stored = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).first,
                  stored.kindRaw == JournalEntryKind.reflection.rawValue else { return }
            let media = stored.mediaFileNames
            do {
                ctx.delete(stored)
                try writeReflectionContext(ctx)
            } catch { ctx.rollback(); throw error }
            // Keep media until the record deletion commits. A failed cleanup leaves
            // removable orphan bytes, never a live reflection with missing media.
            for name in media { try? FileManager.default.removeItem(at: Self.mediaURL(name)) }
        }
    }
    /// Non-throwing single lookup kept for intents and internal maintenance; user-facing detail
    /// uses `readEntry(_:)` so a read failure cannot look like a deleted entry.
    func entry(_ id: String) -> JournalEntry? { try? readEntry(id) }
    func update(_ entry: JournalEntry, text: String) {
        _ = try? writerBoundary.withEffect {
            guard entry.kindRaw == JournalEntryKind.reflection.rawValue, let container else { return }
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let id = entry.id
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            guard let stored = try ctx.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).first,
                  stored.kindRaw == JournalEntryKind.reflection.rawValue else { return }
            let editedAt = Date()
            stored.text = text; stored.editedAt = editedAt
            do { try writeReflectionContext(ctx) }
            catch { ctx.rollback(); throw error }
            entry.text = text; entry.editedAt = editedAt
        }
    }
    /// Entry saved from Siri/Shortcuts, keeping location and media (media files live in Application Support/JournalMedia).
    @discardableResult
    func saveFromIntent(title: String?, text: String, date: Date?, state: HealthState, locationName: String?, latitude: Double?, longitude: Double?,
                        media: [(data: Data, ext: String)]) -> JournalEntry? {
        try? writerBoundary.withEffect {
            guard let container, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ManualJournalSaveError.unavailable
            }
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            let entry = JournalEntry(createdAt: date ?? .now, prompt: title ?? "Note from Siri", text: text, state: state, source: .siri)
            entry.locationName = locationName; entry.latitude = latitude; entry.longitude = longitude
            try FileManager.default.createDirectory(at: Self.mediaDir, withIntermediateDirectories: true)
            do {
                for item in media.prefix(10) {
                    let ext = item.ext.isEmpty ? "jpg" : item.ext
                    guard ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw ManualJournalSaveError.failed }
                    let name = "\(entry.id)-\(UUID().uuidString).\(ext)"
                    let url = Self.mediaURL(name)
                    try item.data.write(to: url, options: .atomic)
                    entry.mediaFileNames.append(name)
                }
                ctx.insert(entry)
                try writeReflectionContext(ctx)
                return entry
            } catch {
                ctx.rollback()
                // A save hook may throw after a durable commit. Retain created media
                // on an uncertain outcome rather than delete bytes a live row may own.
                throw error
            }
        }
    }
    nonisolated static var mediaDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JournalMedia", isDirectory: true)
    }
    nonisolated static func mediaURL(_ name: String) -> URL { mediaDir.appendingPathComponent(name) }
}

/// Image-generation prompts are not journal entries. Apple Intelligence can route any "create a journal entry" request
/// (journal.createEntry schema) to Ate, including Image Playground / Shortcuts model output, which is how an
/// "A top-down, highly detailed photograph…" prompt ended up in the journal (10 Oct). Reject those.
enum JournalTextGuard {
    static func looksLikeImagePrompt(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["highly detailed", "photorealistic", "top-down", "overhead shot", "4k", "8k", "studio lighting", "depth of field",
                       "shallow focus", "bokeh", "food photography", "hyperrealistic", "cinematic lighting", "rendered", "octane", "plated food",
                       "photograph of", "a photo of", "an image of", "illustration of", "aspect ratio", "--ar"]
        let hits = markers.filter { t.contains($0) }.count
        let startsLikePrompt = ["a top-down", "a highly detailed", "a photorealistic", "a close-up photograph", "an overhead", "a photograph of", "generate an image", "create an image"].contains { t.hasPrefix($0) }
        return startsLikePrompt || hits >= 2
    }
}


enum ManualJournalSaveError: LocalizedError {
    case empty, unavailable, failed
    var errorDescription: String? {
        switch self {
        case .empty: return "Write something before saving."
        case .unavailable: return "Your journal cannot save to this iPhone right now. Your draft is still here."
        case .failed: return "Your entry could not be saved. Your draft is still here. Try again."
        }
    }
}
