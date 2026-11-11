import Foundation
import SwiftData

/// Captured completion context, never reconstructed from today's recipe or current clock on retry.
struct CookedJournalReflectionContext: Equatable {
    let eventID: String
    let completedAt: Date
    let recipeSnapshot: JournalRecipeSnapshot
}

enum CookedJournalReflectionError: Error, Equatable {
    case invalidContext, emptyText, unavailable, conflictingIdentity, verificationFailed
}

/// Optional reflection only: cooking never implies eaten food, nutrition, or a Health reading.
/// Stable event-linked identity makes a repeated Save after an uncertain response idempotent.
@MainActor
final class CookedJournalReflectionStore {
    let journal: JournalStore
    private let writerBoundary: FoodJournalWriterBoundary
    private let save: (ModelContext) throws -> Void

    init(journal: JournalStore, writerBoundary: FoodJournalWriterBoundary = .legacy, save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.writerBoundary = writerBoundary
        self.journal = journal
        self.save = save
    }

    @discardableResult
    func save(text: String, context: CookedJournalReflectionContext) throws -> String {
        return try writerBoundary.withEffect {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw CookedJournalReflectionError.emptyText }
            let snapshot = context.recipeSnapshot
            guard !context.eventID.isEmpty, !snapshot.recipeID.isEmpty, !snapshot.title.isEmpty,
                  let day = snapshot.cookedDayKey, FoodJournalStore.validDayKey(day),
                  context.completedAt.timeIntervalSince1970.isFinite else {
                throw CookedJournalReflectionError.invalidContext
            }
            // Unlike a session-only manual note, a queued cook must not be acknowledged from
            // an in-memory fallback. A recovered durable store keeps its own visible warning.
            switch journal.openState {
            case .ok, .recovered: break
            case .inMemoryFallback, .unavailable: throw CookedJournalReflectionError.unavailable
            }
            guard let container = journal.container else { throw CookedJournalReflectionError.unavailable }
            let id = "cook-reflection-" + context.eventID
            let encoded = try JournalRecipeSnapshotCodec.encode([snapshot])
            let transaction = ModelContext(container)
            transaction.autosaveEnabled = false
            func matches(_ row: JournalEntry) -> Bool {
                row.kindRaw == JournalEntryKind.reflection.rawValue && row.createdAt == context.completedAt &&
                    row.dayKey == day && row.text == trimmed && row.prompt.isEmpty && row.stateRaw.isEmpty &&
                    row.recipeIDs == [snapshot.recipeID] && row.recipeSnapshotsRaw == encoded &&
                    row.sourceRaw == JournalEntrySource.ate.rawValue
            }
            let existing = try transaction.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id }))
            if let row = existing.first {
                guard existing.count == 1, matches(row) else {
                    throw CookedJournalReflectionError.conflictingIdentity
                }
                return id
            }
            let row = JournalEntry(id: id, createdAt: context.completedAt, prompt: "", text: trimmed,
                                   state: nil, recipeIDs: [snapshot.recipeID])
            row.dayKey = day
            row.recipeSnapshotsRaw = encoded
            transaction.insert(row)
            do {
                try save(transaction)
                let fresh = ModelContext(container)
                let verified = try fresh.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id }))
                guard verified.count == 1, let row = verified.first, matches(row) else {
                    throw CookedJournalReflectionError.verificationFailed
                }
            }
            catch { transaction.rollback(); throw error }
            return id

        }
    }
}
