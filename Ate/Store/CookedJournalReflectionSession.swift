import Foundation
import Observation

/// One retained outbox event and its draft. Neither the clock nor the live recipe may replace this context.
/// No automatic drain: pending cooks remain available until an explicit optional reflection is saved.
@Observable @MainActor
final class CookedJournalReflectionSession {
    let event: CookCompletionEvent
    var draft: String
    private(set) var problem: String?
    private(set) var isSaved = false
    private let reflections: CookedJournalReflectionStore
    private let outbox: CookCompletionOutbox
    private let acknowledge: (String) throws -> Void
    private var confirmedText: String?
    var isAcknowledgementPending: Bool { confirmedText != nil && !isSaved }

    init(event: CookCompletionEvent, reflections: CookedJournalReflectionStore,
         outbox: CookCompletionOutbox, existingDraft: String = "", acknowledge: ((String) throws -> Void)? = nil) {
        self.event = event
        self.reflections = reflections
        self.outbox = outbox
        self.acknowledge = acknowledge ?? { try outbox.acknowledge(id: $0) }
        self.draft = CookReflectionDraft.prefill(existing: existingDraft, recipeTitle: event.recipeTitle)
    }

    /// The queue must still contain the exact captured event before any write. On uncertainty keep the draft
    /// and event unchanged. A retry uses the same stable identity and payload, including after a committed save.
    @discardableResult
    func save() -> Bool {
        guard !isSaved else { return true }
        do {
            if let confirmedText, draft != confirmedText {
                throw CookedJournalReflectionError.conflictingIdentity
            }
            let queued = try outbox.load().first(where: { $0.id == event.id })
            // Initial saves still require exact queue ownership. Only this retained session's verified
            // reflection phase can finish after an acknowledgement removed the queue but threw on readback.
            guard queued == event || (queued == nil && confirmedText != nil) else {
                throw CookedJournalReflectionError.conflictingIdentity
            }
            let context = CookedJournalReflectionContext(eventID: event.id, completedAt: event.completedAt,
                                                        recipeSnapshot: event.recipeSnapshot)
            let intendedText = confirmedText ?? draft
            _ = try reflections.save(text: intendedText, context: context)
            confirmedText = intendedText
            // Verify the same committed reflection again on retry before treating queue absence as completion.
            if queued != nil { try acknowledge(event.id) }
            isSaved = true
            problem = nil
            draft = ""
            return true
        } catch {
            problem = "Ate could not confirm the whole save. Your note may already be saved. Your draft is still here. Try again without changing the note."
            return false
        }
    }
}
