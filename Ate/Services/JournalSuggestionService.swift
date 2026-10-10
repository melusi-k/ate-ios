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

/// Local SwiftData store for Ate journal entries (in-memory during UI tests). Never synced.
@MainActor
final class JournalStore {
    static let shared = JournalStore()
    let container: ModelContainer?
    init(inMemory: Bool = AppConfig.isUITesting) {
        container = try? ModelContainer(for: JournalEntry.self,
                                        configurations: ModelConfiguration("AteJournal", isStoredInMemoryOnly: inMemory))
        seedMomentEntryForUITests()
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
    func delete(_ e: JournalEntry) { container?.mainContext.delete(e); try? container?.mainContext.save() }
}
