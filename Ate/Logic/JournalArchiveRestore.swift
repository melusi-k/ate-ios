import Foundation
import SwiftData

/// PREP ONLY. Not wired to AppStore. Does not promise crash-atomic restore.
/// apply/rollback must cover EVERY outer archive store, including raw legacy bytes.
@MainActor
struct ArchiveRestoreParticipant {
    let apply: () throws -> Void
    let verify: () throws -> Void
    let rollback: () throws -> Void
}

/// The implementation must never replace an existing destination, follow symlinks,
/// or remove a destination it did not create. Tests inject this boundary.
/// No production implementation is supplied: import TOCTOU review remains a blocker.
@MainActor
protocol ArchiveMediaTransaction: AnyObject {
    func stage(_ media: [String: Data]) throws
    func publish() throws
    func verify() throws
    func rollback() throws
    func finish() throws
}

enum ArchiveRestoreBoundary: CaseIterable, Equatable {
    case beforeStage, afterStage, beforeDatabase, afterDatabase
    case beforeMediaPublish, afterMediaPublish, beforeOuter, afterOuter
    case beforeVerification, afterVerification
}

enum ArchiveRestoreFailure: Error {
    case unavailable, invalidMealDay, existingKindConflict, changedDuringRestore
    case verificationFailed
    /// Original failure plus ALL failed compensations. Never report "nothing imported".
    case recoveryRequired(original: String, compensationFailures: [String])
}

@MainActor
struct JournalArchiveRestorePlan {
    let archive: JournalArchive
    let skippedExisting: Int
}

@MainActor
enum JournalArchiveRestore {
    /// Existing-ID-wins is inherited from AppStore's additive import contract.
    /// A same-ID different-kind record is an unsafe inconsistency, not a silent skip.
    static func prepare(_ incoming: JournalArchive, journal: JournalStore) throws -> JournalArchiveRestorePlan {
        try JournalArchiveCapture.requireCompleteStore(journal.openState)
        guard let container = journal.container else { throw ArchiveRestoreFailure.unavailable }
        try JournalArchiveValidation.validate(incoming)
        guard incoming.entries.compactMap(\.meal).allSatisfy(FoodJournalStore.validMeal) else {
            throw ArchiveRestoreFailure.invalidMealDay
        }
        // Refuse orphan/poisoned local payloads before considering additive IDs.
        _ = try FoodJournalStore(container: container).readMeals()
        let local = try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
        let existing = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0.kindRaw) })
        for row in incoming.entries {
            if let kind = existing[row.id], kind != row.kindRaw {
                throw ArchiveRestoreFailure.existingKindConflict
            }
        }
        let added = incoming.entries.filter { existing[$0.id] == nil }
        let names = Set(added.flatMap(\.mediaFileNames))
        var selected = incoming
        selected.entries = added
        selected.media = incoming.media.filter { names.contains($0.key) }
        selected.mediaSHA256 = incoming.mediaSHA256.filter { names.contains($0.key) }
        return JournalArchiveRestorePlan(archive: selected,
                                        skippedExisting: incoming.entries.count - added.count)
    }

    /// No await inside commit: the MainActor cannot interleave UI writes.
    /// Other processes and process termination still require a durable recovery protocol.
    /// beforeCompensation is mandatory: production composition must durably record
    /// the undo decision, including after a failed finish, before returning. A no-op
    /// is only appropriate for isolated tests, never production recovery wiring.
    static func execute(_ plan: JournalArchiveRestorePlan, journal: JournalStore,
                        media: ArchiveMediaTransaction, outer: ArchiveRestoreParticipant,
                        beforeCompensation: () throws -> Void,
                        checkpoint: (ArchiveRestoreBoundary) throws -> Void = { _ in },
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Int {
        try JournalArchiveCapture.requireCompleteStore(journal.openState)
        guard let container = journal.container else { throw ArchiveRestoreFailure.unavailable }
        // Revalidate public value plan; callers must not be able to bypass prepare.
        try JournalArchiveValidation.validate(plan.archive)
        guard plan.archive.entries.compactMap(\.meal).allSatisfy(FoodJournalStore.validMeal) else {
            throw ArchiveRestoreFailure.invalidMealDay
        }
        _ = try FoodJournalStore(container: container).readMeals()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let existingIDs = Set(try context.fetch(FetchDescriptor<JournalEntry>()).map(\.id))
        guard plan.archive.entries.allSatisfy({ !existingIDs.contains($0.id) }) else {
            throw ArchiveRestoreFailure.changedDuringRestore
        }
        var databaseAttempted = false
        var outerAttempted = false
        do {
            try checkpoint(.beforeStage)
            try media.stage(plan.archive.media)
            try checkpoint(.afterStage)
            try checkpoint(.beforeDatabase)
            for value in plan.archive.entries { insert(value, into: context) }
            databaseAttempted = true // save can throw after a durable write: compensate either way.
            try save(context)
            try checkpoint(.afterDatabase)
            try checkpoint(.beforeMediaPublish)
            try media.publish()
            try checkpoint(.afterMediaPublish)
            try checkpoint(.beforeOuter)
            outerAttempted = true
            try outer.apply()
            try checkpoint(.afterOuter)
            try checkpoint(.beforeVerification)
            try verify(plan.archive.entries, container: container)
            try media.verify()
            try outer.verify()
            try checkpoint(.afterVerification)
            try media.finish()
            return plan.archive.entries.count
        } catch {
            let original = error
            // Persist the global undo intent BEFORE any rollback, including the
            // context rollback. If this fails, retain the partial state and receipts
            // for visible recovery. Never undo under an unrecorded decision.
            do { try beforeCompensation() }
            catch {
                throw ArchiveRestoreFailure.recoveryRequired(
                    original: String(describing: original),
                    compensationFailures: ["compensation intent: \(error)"])
            }
            context.rollback()
            var failures: [String] = []
            // Roll back independently: one failed compensation must not suppress others.
            if outerAttempted {
                do { try outer.rollback() } catch { failures.append("outer: \(error)") }
            }
            if databaseAttempted {
                do { try compensate(plan.archive.entries, container: container, save: save) }
                catch { failures.append("journal: \(error)") }
            }
            do { try media.rollback() } catch { failures.append("media: \(error)") }
            if !failures.isEmpty {
                throw ArchiveRestoreFailure.recoveryRequired(original: String(describing: original),
                                                             compensationFailures: failures)
            }
            throw original
        }
    }

    private static func insert(_ v: JournalArchiveEntry, into ctx: ModelContext) {
        let row = JournalEntry(id: v.id, createdAt: v.createdAt, prompt: v.prompt,
                               text: v.text, state: .balanced, recipeIDs: v.recipeIDs,
                               journalingSuggestionTitle: v.journalingSuggestionTitle,
                               momentDate: v.momentDate)
        // Constructor enums are not data normalization. Persist every raw value verbatim.
        row.stateRaw = v.stateRaw; row.sourceRaw = v.sourceRaw; row.kindRaw = v.kindRaw
        row.locationName = v.locationName; row.latitude = v.latitude; row.longitude = v.longitude
        row.mediaFileNames = v.mediaFileNames; row.editedAt = v.editedAt
        row.dayKey = v.dayKey; row.recipeSnapshotsRaw = v.recipeSnapshotsRaw
        ctx.insert(row)
        if let m = v.meal {
            ctx.insert(JournalMealPayload(entryID: v.id, meal: m.meal, foodName: m.foodName,
                quantity: m.quantity, quantityUnit: m.quantityUnit, servings: m.servings,
                source: m.source, sourceName: m.sourceName, sourceIdentifier: m.sourceIdentifier,
                verificationNote: m.verificationNote, nutrients: m.nutrientsPerServing))
        }
    }

    private static func value(_ row: JournalEntry, meal: NutritionDiaryEntry?) -> JournalArchiveEntry {
        JournalArchiveEntry(id: row.id, createdAt: row.createdAt, prompt: row.prompt, text: row.text,
            stateRaw: row.stateRaw, recipeIDs: row.recipeIDs,
            journalingSuggestionTitle: row.journalingSuggestionTitle, momentDate: row.momentDate,
            sourceRaw: row.sourceRaw, locationName: row.locationName, latitude: row.latitude,
            longitude: row.longitude, mediaFileNames: row.mediaFileNames, editedAt: row.editedAt,
            kindRaw: row.kindRaw, dayKey: row.dayKey, recipeSnapshotsRaw: row.recipeSnapshotsRaw, meal: meal)
    }

    /// Fresh ModelContext read, NOT physical store close/reopen proof.
    private static func verify(_ expected: [JournalArchiveEntry], container: ModelContainer) throws {
        let context = ModelContext(container)
        let rows = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<JournalEntry>()).map { ($0.id, $0) })
        let meals = Dictionary(uniqueKeysWithValues: try FoodJournalStore(container: container).readMeals().map { ($0.id.uuidString, $0) })
        for v in expected {
            guard let row = rows[v.id], value(row, meal: meals[v.id]) == v else {
                throw ArchiveRestoreFailure.verificationFailed
            }
        }
    }

    private static func compensate(_ inserted: [JournalArchiveEntry], container: ModelContainer,
                                   save: (ModelContext) throws -> Void) throws {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let expected = Dictionary(uniqueKeysWithValues: inserted.map { ($0.id, $0) })
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>()).filter { expected[$0.id] != nil }
        let payloads = try ctx.fetch(FetchDescriptor<JournalMealPayload>()).filter { expected[$0.entryID] != nil }
        let meals = Dictionary(uniqueKeysWithValues: try FoodJournalStore(container: container).readMeals().map { ($0.id.uuidString, $0) })
        // Refuse to erase another writer's edits, even while compensating.
        guard rows.allSatisfy({ value($0, meal: meals[$0.id]) == expected[$0.id] }) else {
            throw ArchiveRestoreFailure.changedDuringRestore
        }
        for row in rows { ctx.delete(row) }
        for payload in payloads { ctx.delete(payload) }
        try save(ctx)
        let check = ModelContext(container)
        guard try check.fetch(FetchDescriptor<JournalEntry>()).allSatisfy({ expected[$0.id] == nil }),
              try check.fetch(FetchDescriptor<JournalMealPayload>()).allSatisfy({ expected[$0.entryID] == nil }) else {
            throw ArchiveRestoreFailure.verificationFailed
        }
    }
}
