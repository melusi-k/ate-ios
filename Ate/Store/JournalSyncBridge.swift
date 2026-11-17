import Foundation
import SwiftData

/// Export/apply bridge between the local SwiftData journal container and
/// `JournalEntrySyncPayload` rows for cloud sync (issue #34).
///
/// This is the ONLY sync boundary for journal content: it never decides sync policy
/// (that is `UserDataSyncPlanner`) and never writes anywhere but the local container it is
/// given. Row mapping is full-fidelity: every `JournalEntry` field and the one-to-one
/// `JournalMealPayload` round-trips, and recipe snapshots travel as their stored
/// `recipeSnapshotsRaw` string so no codec version decision is made here.
///
/// Media bytes stay local (phase 1): `mediaFileNames` syncs as references only, and a
/// restored entry pointing at files this device never captured simply shows no media -
/// the same presentation as a locally missing file.
@MainActor
enum JournalSyncBridge {
    enum BridgeError: Error, Equatable {
        case storeUnavailable
        case unreadableRow(String)
        case saveFailed
    }

    private static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// Every journal row (meals AND reflections) as sync payloads. Throws rather than
    /// returning a partial export: a partial export would make deletion detection treat
    /// the missing rows as locally deleted and push tombstones for live entries.
    static func export(container: ModelContainer?) throws -> [JournalEntrySyncPayload] {
        guard let container else { throw BridgeError.storeUnavailable }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let entries: [JournalEntry]
        let payloads: [JournalMealPayload]
        do {
            entries = try context.fetch(FetchDescriptor<JournalEntry>())
            payloads = try context.fetch(FetchDescriptor<JournalMealPayload>())
        } catch { throw BridgeError.storeUnavailable }
        let payloadByEntry = Dictionary(payloads.map { ($0.entryID, $0) }, uniquingKeysWith: { a, _ in a })
        return try entries.map { entry in
            // A meal row without its payload (or a reflection carrying one) is exactly the
            // corruption FoodJournalStore.readMeals refuses to serve; sync must not either.
            let mealPayload: JournalMealPayload?
            switch entry.kind {
            case .meal:
                guard let payload = payloadByEntry[entry.id] else { throw BridgeError.unreadableRow(entry.id) }
                mealPayload = payload
            case .reflection:
                guard payloadByEntry[entry.id] == nil else { throw BridgeError.unreadableRow(entry.id) }
                mealPayload = nil
            }
            return JournalEntrySyncPayload(
                id: entry.id,
                createdAtMs: ms(entry.createdAt),
                prompt: entry.prompt,
                text: entry.text,
                stateRaw: entry.stateRaw,
                recipeIDs: entry.recipeIDs,
                journalingSuggestionTitle: entry.journalingSuggestionTitle,
                momentDateMs: entry.momentDate.map(ms),
                sourceRaw: entry.sourceRaw,
                locationName: entry.locationName,
                latitude: entry.latitude,
                longitude: entry.longitude,
                mediaFileNames: entry.mediaFileNames,
                editedAtMs: entry.editedAt.map(ms),
                kindRaw: entry.kindRaw,
                dayKey: entry.dayKey,
                recipeSnapshotsRaw: entry.recipeSnapshotsRaw,
                meal: mealPayload.map {
                    JournalMealSyncPayload(
                        mealRaw: $0.mealRaw, foodName: $0.foodName, quantity: $0.quantity,
                        quantityUnit: $0.quantityUnit, servings: $0.servings, sourceRaw: $0.sourceRaw,
                        sourceName: $0.sourceName, sourceIdentifier: $0.sourceIdentifier,
                        verificationNote: $0.verificationNote, energyKcal: $0.energyKcal,
                        proteinGrams: $0.proteinGrams, carbohydratesGrams: $0.carbohydratesGrams,
                        fatGrams: $0.fatGrams, fibreGrams: $0.fibreGrams)
                })
        }
    }

    /// Applies the planner's local-side result. Upserts overwrite whole rows (LWW already
    /// decided the winner); deletes remove entry + meal payload together. One context, one
    /// save: a failed save rolls back so the timeline never shows a half-applied round.
    /// The merge's stamps are persisted by the caller only after this save succeeds.
    static func apply(upserts: [JournalEntrySyncPayload], deletes: [String], container: ModelContainer?) throws {
        guard let container else { throw BridgeError.storeUnavailable }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            for id in deletes {
                if let row = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == id })).first {
                    context.delete(row)
                }
                if let payload = try context.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == id })).first {
                    context.delete(payload)
                }
            }
            for payload in upserts {
                let row: JournalEntry
                if let existing = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == payload.id })).first {
                    row = existing
                } else {
                    // The designated init supplies prompt/text/state; every other field is
                    // assigned below from the payload, so no default survives the upsert.
                    let created = JournalEntry(id: payload.id, createdAt: date(payload.createdAtMs),
                                               prompt: payload.prompt, text: payload.text,
                                               state: HealthState(rawValue: payload.stateRaw),
                                               recipeIDs: payload.recipeIDs)
                    context.insert(created)
                    row = created
                }
                row.createdAt = date(payload.createdAtMs)
                row.prompt = payload.prompt
                row.text = payload.text
                row.stateRaw = payload.stateRaw
                row.recipeIDs = payload.recipeIDs
                row.journalingSuggestionTitle = payload.journalingSuggestionTitle
                row.momentDate = payload.momentDateMs.map(date)
                row.sourceRaw = payload.sourceRaw
                row.locationName = payload.locationName
                row.latitude = payload.latitude
                row.longitude = payload.longitude
                row.mediaFileNames = payload.mediaFileNames
                row.editedAt = payload.editedAtMs.map(date)
                row.kindRaw = payload.kindRaw
                row.dayKey = payload.dayKey
                // Raw assignment, not setRecipeSnapshots: sync restores a previously stored
                // payload verbatim and an empty/undecodable local row must not refuse it.
                row.recipeSnapshotsRaw = payload.recipeSnapshotsRaw

                let existingMeal = try context.fetch(FetchDescriptor<JournalMealPayload>(predicate: #Predicate { $0.entryID == payload.id })).first
                if let meal = payload.meal {
                    let target = existingMeal ?? JournalMealPayload(
                        entryID: payload.id, meal: NutritionMeal(rawValue: meal.mealRaw) ?? .snack,
                        foodName: meal.foodName, quantity: meal.quantity, quantityUnit: meal.quantityUnit,
                        servings: meal.servings, source: NutritionEntrySource(rawValue: meal.sourceRaw) ?? .userProvided,
                        sourceName: meal.sourceName, sourceIdentifier: meal.sourceIdentifier,
                        verificationNote: meal.verificationNote,
                        nutrients: NutritionSnapshot(energyKcal: meal.energyKcal, proteinGrams: meal.proteinGrams,
                                                     carbohydratesGrams: meal.carbohydratesGrams,
                                                     fatGrams: meal.fatGrams, fibreGrams: meal.fibreGrams))
                    if existingMeal == nil { context.insert(target) }
                    target.mealRaw = meal.mealRaw
                    target.foodName = meal.foodName
                    target.quantity = meal.quantity
                    target.quantityUnit = meal.quantityUnit
                    target.servings = meal.servings
                    target.sourceRaw = meal.sourceRaw
                    target.sourceName = meal.sourceName
                    target.sourceIdentifier = meal.sourceIdentifier
                    target.verificationNote = meal.verificationNote
                    target.energyKcal = meal.energyKcal
                    target.proteinGrams = meal.proteinGrams
                    target.carbohydratesGrams = meal.carbohydratesGrams
                    target.fatGrams = meal.fatGrams
                    target.fibreGrams = meal.fibreGrams
                } else if let existingMeal {
                    // A reflection carrying a meal payload is not a valid row; the remote
                    // winner says it is a reflection, so the orphan payload goes.
                    context.delete(existingMeal)
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw BridgeError.saveFailed
        }
    }
}
