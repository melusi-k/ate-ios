import Foundation
import SwiftData

/// PREP ONLY. No production call sites; component participant, not the full outer.
/// Raw store-level transaction for RecipeEntity/ShoppingEntity. Existing entities keep
/// exact json bytes; new archive entries are pre-encoded before any store write.
/// In-memory array assignment, stampChanges/sync scheduling, widget/shortcut side
/// effects are activation wiring and deliberately absent here.
@MainActor
final class ArchiveRecipeShoppingParticipant {
    enum Boundary: CaseIterable, Equatable { case beforeCommit, afterCommit, beforeVerify }
    enum Failure: Error { case changedSinceSnapshot, readbackMismatch }

    /// Exact raw entity triple. Positions are store ordering, identities are ids, json
    /// bytes are preserved verbatim (never re-encoded for existing rows).
    struct RawRecipe: Equatable { let id: String; let createdAt: Double; let position: Int; let json: Data }
    struct RawShopping: Equatable { let id: String; let position: Int; let json: Data }

    private let container: ModelContainer
    private let before: (recipes: [RawRecipe], shopping: [RawShopping])
    private let planned: (recipes: [RawRecipe], shopping: [RawShopping])
    private let addedIDs: (recipes: Set<String>, shopping: Set<String>)
    private let checkpoint: (Boundary) throws -> Void
    private let save: (ModelContext) throws -> Void
    /// Bound to lease.validate at composition. Called BEFORE EVERY mutation and
    /// every undo write - a failed validation STOPS compensation and surfaces
    /// recoveryRequired rather than guessing about foreign state.
    private let validate: () throws -> Void
    private var attempted = false

    /// Snapshots the store with throwing fetches, merges incoming existing-ID-wins, and
    /// pre-encodes every new entity. No store write happens in init.
    init(container: ModelContainer, incomingRecipes: [RecipeCard], incomingShopping: [ShoppingItem],
         checkpoint: @escaping (Boundary) throws -> Void = { _ in },
         save: @escaping (ModelContext) throws -> Void = { try $0.save() },
         validate: @escaping () throws -> Void = {}) throws {
        self.container = container; self.checkpoint = checkpoint; self.save = save
        self.validate = validate
        let read = ModelContext(container); read.autosaveEnabled = false
        let recipeRows: [RecipeEntity] = try read.fetch(FetchDescriptor<RecipeEntity>())
        let recipeCopies: [RawRecipe] = recipeRows.map { row in
            RawRecipe(id: row.id, createdAt: row.createdAt, position: row.position, json: row.json)
        }
        let recipes: [RawRecipe] = recipeCopies.sorted(by: Self.recipeOrder)
        let shoppingRows: [ShoppingEntity] = try read.fetch(FetchDescriptor<ShoppingEntity>())
        let shoppingCopies: [RawShopping] = shoppingRows.map { row in
            RawShopping(id: row.id, position: row.position, json: row.json)
        }
        let shopping: [RawShopping] = shoppingCopies.sorted(by: Self.shoppingOrder)
        before = (recipes, shopping)

        // Merge rules mirror importJSON at the store layer: existing id wins and is
        // never re-encoded; contentless recipes are skipped; new recipes prepend as a
        // reversed batch (importCards insert-at-0 semantics); new shopping appends.
        var recipeIDs = Set(recipes.map(\.id))
        let freshRecipes = incomingRecipes.filter { recipeIDs.insert($0.id).inserted }
        let importable = freshRecipes
            .filter { !($0.ingredients.isEmpty && $0.steps.isEmpty) }
            .map(RecipeLogic.normalize)
        var shopIDs = Set(shopping.map(\.id))
        let freshShopping = incomingShopping.filter { shopIDs.insert($0.id).inserted }

        let enc = JSONEncoder()
        var plannedRecipes: [RawRecipe] = try importable.reversed().map {
            RawRecipe(id: $0.id, createdAt: $0.createdAt, position: 0, json: try enc.encode($0))
        }
        plannedRecipes.append(contentsOf: recipes.map { RawRecipe(id: $0.id, createdAt: $0.createdAt, position: 0, json: $0.json) })
        for i in plannedRecipes.indices { plannedRecipes[i] = RawRecipe(id: plannedRecipes[i].id, createdAt: plannedRecipes[i].createdAt, position: i, json: plannedRecipes[i].json) }
        var plannedShopping = shopping
        for item in freshShopping {
            plannedShopping.append(RawShopping(id: item.id, position: plannedShopping.count, json: try enc.encode(item)))
        }
        planned = (plannedRecipes, plannedShopping)
        addedIDs = (Set(importable.map(\.id)), Set(freshShopping.map(\.id)))
    }

    func participant() -> ArchiveRestoreParticipant {
        ArchiveRestoreParticipant(apply: { try self.apply() }, verify: { try self.verify() },
                                  rollback: { try self.rollback() })
    }

    private static func recipeOrder(_ lhs: RawRecipe, _ rhs: RawRecipe) -> Bool {
        if lhs.position == rhs.position { return lhs.id < rhs.id }
        return lhs.position < rhs.position
    }
    private static func shoppingOrder(_ lhs: RawShopping, _ rhs: RawShopping) -> Bool {
        if lhs.position == rhs.position { return lhs.id < rhs.id }
        return lhs.position < rhs.position
    }

    private func snapshot() throws -> (recipes: [RawRecipe], shopping: [RawShopping]) {
        let read = ModelContext(container); read.autosaveEnabled = false
        let recipeRows: [RecipeEntity] = try read.fetch(FetchDescriptor<RecipeEntity>())
        let recipeCopies: [RawRecipe] = recipeRows.map { row in
            RawRecipe(id: row.id, createdAt: row.createdAt, position: row.position, json: row.json)
        }
        let r: [RawRecipe] = recipeCopies.sorted(by: Self.recipeOrder)
        let shoppingRows: [ShoppingEntity] = try read.fetch(FetchDescriptor<ShoppingEntity>())
        let shoppingCopies: [RawShopping] = shoppingRows.map { row in
            RawShopping(id: row.id, position: row.position, json: row.json)
        }
        let s: [RawShopping] = shoppingCopies.sorted(by: Self.shoppingOrder)
        return (r, s)
    }

    /// One isolated autosave-disabled context, one throwing save. Existing rows are
    /// rewritten only because positions reindex; their json bytes stay byte-identical.
    private func apply() throws {
        guard !attempted else { throw Failure.readbackMismatch }
        guard try snapshot() == before else { throw Failure.changedSinceSnapshot }
        attempted = true
        try checkpoint(.beforeCommit)
        let ctx = ModelContext(container); ctx.autosaveEnabled = false
        // Context-tracked per-row rewrites, NOT delete(model:): the batch form deletes
        // directly against the store immediately, escaping this one guarded save, and
        // delete+reinsert of the same @Attribute(.unique) id in one save races the
        // upsert against a pending deletion. Existing rows update in place; only new
        // ids insert; only removed ids delete; everything persists in the save below.
        // Validation points keep the pre-fix count and first/before-save positions:
        // 1 + planned-recipe writes + 1 + planned-shopping writes + 1 = 3 + P_r + P_s.
        // Every throw before the durable save discards pending context writes.
        do {
            try validate()
            let existingRecipes = try ctx.fetch(FetchDescriptor<RecipeEntity>())
            let existingRecipeByID = Dictionary(uniqueKeysWithValues: existingRecipes.map { ($0.id, $0) })
            let plannedRecipeIDs = Set(planned.recipes.map(\.id))
            for r in planned.recipes {
                try validate()
                if let row = existingRecipeByID[r.id] {
                    row.createdAt = r.createdAt; row.position = r.position; row.json = r.json
                } else {
                    ctx.insert(RecipeEntity(id: r.id, createdAt: r.createdAt, position: r.position, json: r.json))
                }
            }
            for row in existingRecipes where !plannedRecipeIDs.contains(row.id) { ctx.delete(row) }
            try validate()
            let existingShopping = try ctx.fetch(FetchDescriptor<ShoppingEntity>())
            let existingShoppingByID = Dictionary(uniqueKeysWithValues: existingShopping.map { ($0.id, $0) })
            let plannedShoppingIDs = Set(planned.shopping.map(\.id))
            for s in planned.shopping {
                try validate()
                if let row = existingShoppingByID[s.id] {
                    row.position = s.position; row.json = s.json
                } else {
                    ctx.insert(ShoppingEntity(id: s.id, position: s.position, json: s.json))
                }
            }
            for row in existingShopping where !plannedShoppingIDs.contains(row.id) { ctx.delete(row) }
            try validate()
            try save(ctx)
        } catch {
            ctx.rollback() // discard every write the durable save never committed
            throw error
        }
        try checkpoint(.afterCommit)
    }

    private func verify() throws {
        try checkpoint(.beforeVerify)
        guard try snapshot() == planned else { throw Failure.readbackMismatch }
    }

    /// Guarded per-entity compensation, matching the Journal compensate contract:
    /// an entity is reverted ONLY when its current bytes equal what this participant
    /// wrote (planned), or already matches the before-image. Anything else is a
    /// concurrent CONTENT edit: the value is PRESERVED and surfaced as
    /// recoveryRequired, never overwritten. Restoring an ABSENT row is safe ONLY
    /// under a validated held lease (no cooperative writer could have deleted it);
    /// validate() runs before every undo write and a failure stops compensation
    /// instead of guessing. Foreign CONTENT is preserved; foreign DELETION is not
    /// distinguishable from a partial save without the lease - that bound is
    /// deliberate. Reconciliation is per-entity, so a mid-save failure leaving any
    /// before/planned mix does not break durable partial compensation.
    private func rollback() throws {
        guard attempted else { return }
        let current = try snapshot()
        let ctx = ModelContext(container); ctx.autosaveEnabled = false
        var failures: [String] = []
        // Every throw before the durable save discards pending context writes, so a
        // stopped compensation never leaves unsaved state behind.
        do {
            let rOutcome = try reconcile(current: current.recipes, before: before.recipes, planned: planned.recipes,
                kind: "recipe", failures: &failures,
                delete: { id in
                    // Context-tracked instance delete, NOT delete(model:where:): the batch
                    // form deletes directly against the store immediately, escaping the
                    // guarded save below - a validation stop would lose the before-image.
                    for row in try ctx.fetch(FetchDescriptor<RecipeEntity>(predicate: #Predicate { $0.id == id })) { ctx.delete(row) }
                },
                insert: { r in ctx.insert(RecipeEntity(id: r.id, createdAt: r.createdAt, position: r.position, json: r.json)) },
                update: { r in
                    let id = r.id
                    for row in try ctx.fetch(FetchDescriptor<RecipeEntity>(predicate: #Predicate { $0.id == id })) {
                        row.createdAt = r.createdAt; row.position = r.position; row.json = r.json
                    }
                })
            let sOutcome = try reconcile(current: current.shopping, before: before.shopping, planned: planned.shopping,
                kind: "shopping", failures: &failures,
                delete: { id in
                    // Context-tracked instance delete, NOT delete(model:where:): the batch
                    // form deletes directly against the store immediately, escaping the
                    // guarded save below - a validation stop would lose the before-image.
                    for row in try ctx.fetch(FetchDescriptor<ShoppingEntity>(predicate: #Predicate { $0.id == id })) { ctx.delete(row) }
                },
                insert: { s in ctx.insert(ShoppingEntity(id: s.id, position: s.position, json: s.json)) },
                update: { s in
                    let id = s.id
                    for row in try ctx.fetch(FetchDescriptor<ShoppingEntity>(predicate: #Predicate { $0.id == id })) {
                        row.position = s.position; row.json = s.json
                    }
                })
            do { try validate() }
            catch {
                failures.append("compensating save: lease validation failed: \(error)")
                throw ArchiveRestoreFailure.recoveryRequired(original: "recipe/shopping rollback interrupted",
                                                             compensationFailures: failures)
            }
            try save(ctx)
            let restored = try snapshot()
            verify(reverted: rOutcome.reverted, removed: rOutcome.removed, preserved: rOutcome.preserved,
                   restored: restored.recipes, kind: "recipe", failures: &failures)
            verify(reverted: sOutcome.reverted, removed: sOutcome.removed, preserved: sOutcome.preserved,
                   restored: restored.shopping, kind: "shopping", failures: &failures)
            if !failures.isEmpty {
                throw ArchiveRestoreFailure.recoveryRequired(original: "recipe/shopping rollback",
                                                             compensationFailures: failures)
            }
        } catch {
            ctx.rollback() // discard every compensation write the durable save never committed
            throw error
        }
    }

    private struct Outcome<E> { var reverted: [String: E] = [:]; var removed: Set<String> = []; var preserved: [String: E] = [:] }

    private func reconcile<E: Equatable>(current: [E], before: [E], planned: [E], kind: String,
                                         failures: inout [String],
                                         delete: (String) throws -> Void,
                                         insert: (E) -> Void,
                                         update: (E) throws -> Void) throws -> Outcome<E> where E: HasStringID {
        var outcome = Outcome<E>()
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let plannedByID = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for id in Set(beforeByID.keys).union(plannedByID.keys).sorted() {
            let b = beforeByID[id], p = plannedByID[id], c = currentByID[id]
            // Any validation error means ownership is unproven. Do not depend
            // on a particular lease implementation's error enum.
            do { try validate() }
            catch {
                failures.append("\(kind) \(id): lease validation failed: \(error)")
                throw ArchiveRestoreFailure.recoveryRequired(original: "\(kind) rollback interrupted",
                                                             compensationFailures: failures)
            }
            do {
                switch (b, p, c) {
                case let (_, _, c?) where c == b: break                 // already before-image
                case let (b?, _, c?) where c == p:                      // our write: revert in place
                    // In-place update of the same row: delete+reinsert of the same
                    // @Attribute(.unique) id in one save races the upsert against a
                    // pending deletion.
                    do { try validate() }
                    catch {
                        failures.append("\(kind) \(id): lease validation failed before revert: \(error)")
                        throw ArchiveRestoreFailure.recoveryRequired(original: "\(kind) rollback interrupted",
                                                                     compensationFailures: failures)
                    }
                    try update(b); outcome.reverted[id] = b
                case let (nil, _, c?) where c == p:                     // our addition: remove
                    try delete(id); outcome.removed.insert(id)
                case let (b?, _, nil) where p != nil:                   // partial save / missing: restore
                    insert(b); outcome.reverted[id] = b
                case (nil, _, nil): break                               // addition never landed
                default:                                                // concurrent edit or deletion: preserve
                    if let c { outcome.preserved[id] = c }
                    failures.append("\(kind) \(id): concurrent change preserved, not reverted")
                }
            } catch let failure as ArchiveRestoreFailure {
                throw failure
            } catch { failures.append("\(kind) \(id): \(error)") }
        }
        return outcome
    }

    private func verify<E: Equatable>(reverted: [String: E], removed: Set<String>, preserved: [String: E],
                                      restored: [E], kind: String, failures: inout [String]) where E: HasStringID {
        let byID = Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0) })
        for (id, e) in reverted where byID[id] != e { failures.append("\(kind) \(id): revert readback mismatch") }
        for id in removed where byID[id] != nil { failures.append("\(kind) \(id): removal readback mismatch") }
        for (id, e) in preserved where byID[id] != e { failures.append("\(kind) \(id): preserved value lost") }
    }
}

private protocol HasStringID { var id: String { get } }
extension ArchiveRecipeShoppingParticipant.RawRecipe: HasStringID {}
extension ArchiveRecipeShoppingParticipant.RawShopping: HasStringID {}
