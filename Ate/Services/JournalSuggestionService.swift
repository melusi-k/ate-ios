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
                if text.count > 8, text.count < 220 { return [JournalPrompt(text: text, state: insight.state, generated: true)] + base.prefix(1) }
            }
        }
        #endif
        return base
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
    let container: ModelContainer?
    private(set) var openState: JournalOpenState
    init(inMemory: Bool = AppConfig.isUITesting) {
        if inMemory {
            container = try? ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                                            configurations: ModelConfiguration("AteJournal", isStoredInMemoryOnly: true))
            openState = container == nil ? .unavailable(error: "the in-memory journal failed to open") : .ok
            // UI tests (`-qaJournalOpenState recovered|fallback|unavailable`): force the presented
            // open state so the honest banner is verifiable through the running app's accessibility
            // tree. Inert in production: qaForcedOpenState returns nil unless AppConfig.isUITesting.
            if let forced = Self.qaForcedOpenState() { openState = forced }
        } else {
            // "AteJournal" has always resolved to this URL in the default directory, so opening
            // by URL keeps every existing entry while giving recovery a path to move aside.
            let outcome = StoreRecovery.open(url: ModelConfiguration("AteJournal").url) { cfg in
                try ModelContainer(for: JournalEntry.self, JournalMealPayload.self, configurations: cfg)
            }
            container = outcome.container
            openState = Self.openState(for: outcome)
        }
        seedMomentEntryForUITests()
        removeImagePromptEntriesOnce()
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
    private func removeImagePromptEntriesOnce() {
        let k = "ate.journal.imagePromptCleanup.v1"
        guard !UserDefaults.standard.bool(forKey: k), let ctx = container?.mainContext else { return }
        for e in entries() where e.source != .journalMoment && JournalTextGuard.looksLikeImagePrompt(e.text) { ctx.delete(e) }
        try? ctx.save(); UserDefaults.standard.set(true, forKey: k)
    }
    func entries() -> [JournalEntry] {
        (try? container?.mainContext.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }
    @discardableResult
    func save(prompt: String, text: String, state: HealthState, recipeIDs: [String], momentTitle: String? = nil, momentDate: Date? = nil) -> Bool {
        guard let ctx = container?.mainContext, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        ctx.insert(JournalEntry(prompt: prompt, text: text, state: state, recipeIDs: recipeIDs, journalingSuggestionTitle: momentTitle,
                                momentDate: momentDate, source: momentTitle == nil ? .ate : .journalMoment))
        return (try? ctx.save()) != nil
    }
    /// UI tests (`-qaJournalMomentEntry`): one entry that came from a Journal moment, to check the context row.
    func seedMomentEntryForUITests() {
        guard AppConfig.isUITesting, ProcessInfo.processInfo.arguments.contains("-qaJournalMomentEntry"), entries().isEmpty else { return }
        if case let .journalEntry(p, title, date, state) = JournalingMomentMapper.map(title: "Dinner at Mama's", date: DateInterval(start: Date(timeIntervalSince1970: 1_791_000_000), duration: 3600), hasPhotos: false, isWorkout: false) {
            save(prompt: p, text: "Seeded from a Journal moment", state: state, recipeIDs: [], momentTitle: title, momentDate: date)
        }
    }
    func delete(_ e: JournalEntry) {
        for f in e.mediaFileNames { try? FileManager.default.removeItem(at: Self.mediaURL(f)) }
        if let ctx = container?.mainContext {
            // A meal entry's structured payload goes with it; the timeline never keeps one without the other (#245).
            let entryID = e.id
            if let payload = try? ctx.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == entryID })).first {
                ctx.delete(payload)
            }
            ctx.delete(e); try? ctx.save()
        }
    }
    func entry(_ id: String) -> JournalEntry? { entries().first { $0.id == id } }
    func update(_ e: JournalEntry, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        e.text = t; e.editedAt = .now; try? container?.mainContext.save()
    }
    /// Entry saved from Siri/Shortcuts, keeping location and media (media files live in Application Support/JournalMedia).
    @discardableResult
    func saveFromIntent(title: String?, text: String, date: Date?, state: HealthState, locationName: String?, latitude: Double?, longitude: Double?,
                        media: [(data: Data, ext: String)]) -> JournalEntry? {
        guard let ctx = container?.mainContext, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let e = JournalEntry(createdAt: date ?? .now, prompt: title ?? "Note from Siri", text: text, state: state, source: .siri)
        e.locationName = locationName; e.latitude = latitude; e.longitude = longitude
        try? FileManager.default.createDirectory(at: Self.mediaDir, withIntermediateDirectories: true)
        e.mediaFileNames = media.prefix(10).compactMap { m in
            let name = "\(e.id)-\(UUID().uuidString.prefix(8)).\(m.ext.isEmpty ? "jpg" : m.ext)"
            return (try? m.data.write(to: Self.mediaURL(name))) != nil ? name : nil
        }
        ctx.insert(e)
        return (try? ctx.save()) != nil ? e : nil
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
