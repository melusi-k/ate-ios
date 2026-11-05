import XCTest
import SwiftData
@testable import Ate

/// Synthetic only, UNRUN. Mirrors the checkpoint-loop/durable-throw/changed-source
/// patterns of the nutrition participant tests at the raw recipe/shopping/defaults layer.
@MainActor
final class ArchiveCentralOuterTests: XCTestCase {
    enum Injected: Error { case failure }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func card(_ id: String, empty: Bool = false) -> RecipeCard {
        RecipeCard(id: id, ingredients: empty ? [] : [Ingredient(name: "Pap", quantity: 1, unit: "cup")],
                   steps: empty ? [] : [Step(order: 0, instruction: "Cook")], createdAt: 1234)
    }
    private func item(_ id: String) -> ShoppingItem { ShoppingItem(id: id, name: "Rice", quantity: 1, unit: "kg") }
    @discardableResult
    private func seed(_ c: ModelContainer) throws -> (Data, Data) {
        let weirdRecipe = Data("{\"id\":\"r-old\",trailing-junk".utf8) // undecodable: must survive verbatim
        let weirdShop = Data([0x00, 0xFF])
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        ctx.insert(RecipeEntity(id: "r-old", createdAt: 111, position: 0, json: weirdRecipe))
        ctx.insert(ShoppingEntity(id: "s-old", position: 0, json: weirdShop))
        try ctx.save()
        return (weirdRecipe, weirdShop)
    }
    private func raw(_ c: ModelContainer) throws -> ([ArchiveRecipeShoppingParticipant.RawRecipe],
                                                     [ArchiveRecipeShoppingParticipant.RawShopping]) {
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        let recipeEntities: [RecipeEntity] = try ctx.fetch(FetchDescriptor<RecipeEntity>())
        let mappedRecipes: [ArchiveRecipeShoppingParticipant.RawRecipe] = recipeEntities.map {
            ArchiveRecipeShoppingParticipant.RawRecipe(id: $0.id, createdAt: $0.createdAt, position: $0.position, json: $0.json) }
        let r = mappedRecipes.sorted { (lhs: ArchiveRecipeShoppingParticipant.RawRecipe, rhs: ArchiveRecipeShoppingParticipant.RawRecipe) in
            lhs.position == rhs.position ? lhs.id < rhs.id : lhs.position < rhs.position
        }
        let shoppingEntities: [ShoppingEntity] = try ctx.fetch(FetchDescriptor<ShoppingEntity>())
        let mappedShopping: [ArchiveRecipeShoppingParticipant.RawShopping] = shoppingEntities.map {
            ArchiveRecipeShoppingParticipant.RawShopping(id: $0.id, position: $0.position, json: $0.json) }
        let s = mappedShopping.sorted { (lhs: ArchiveRecipeShoppingParticipant.RawShopping, rhs: ArchiveRecipeShoppingParticipant.RawShopping) in
            lhs.position == rhs.position ? lhs.id < rhs.id : lhs.position < rhs.position
        }
        return (r, s)
    }

    func testEveryBoundaryRestoresExactRawStore() throws {
        for boundary in ArchiveRecipeShoppingParticipant.Boundary.allCases {
            let c = try container(); let seeded = try seed(c)
            let p = try ArchiveRecipeShoppingParticipant(container: c, incomingRecipes: [card("r-new")],
                incomingShopping: [item("s-new")], checkpoint: { if $0 == boundary { throw Injected.failure } })
            XCTAssertThrowsError(try { let w = p.participant(); try w.apply(); try w.verify() }())
            try p.participant().rollback()
            let (r, s) = try raw(c)
            XCTAssertEqual(r.map(\.json), [seeded.0], "\(boundary)")
            XCTAssertEqual(s.map(\.json), [seeded.1], "\(boundary)")
            XCTAssertEqual(r.map(\.position), [0], "\(boundary)")
        }
    }

    func testDurableSaveThenThrowRestoresBeforeImage() throws {
        let c = try container(); let seeded = try seed(c)
        var saves = 0
        let p = try ArchiveRecipeShoppingParticipant(container: c, incomingRecipes: [card("r-new")],
            incomingShopping: [], save: { ctx in try ctx.save(); saves += 1; if saves == 1 { throw Injected.failure } })
        XCTAssertThrowsError(try p.participant().apply())
        try p.participant().rollback()
        XCTAssertEqual(saves, 2)
        XCTAssertEqual(try raw(c).0.map(\.json), [seeded.0])
    }

    func testChangedSourceRefusesAndPreservesConcurrentWrite() throws {
        let c = try container(); _ = try seed(c)
        let p = try ArchiveRecipeShoppingParticipant(container: c, incomingRecipes: [card("r-new")], incomingShopping: [])
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        ctx.insert(ShoppingEntity(id: "s-concurrent", position: 1, json: Data("[]".utf8)))
        try ctx.save()
        XCTAssertThrowsError(try p.participant().apply())
        try p.participant().rollback()
        XCTAssertEqual(try raw(c).1.map(\.id), ["s-old", "s-concurrent"])
    }

    func testMergeExistingWinsSkipsEmptyAndPreservesExistingBytes() throws {
        let c = try container(); let seeded = try seed(c)
        let dup = card("r-old") // existing id wins
        let p = try ArchiveRecipeShoppingParticipant(container: c,
            incomingRecipes: [card("r-a"), dup, card("r-b", empty: true), card("r-c")],
            incomingShopping: [item("s-old"), item("s-new")])
        let w = p.participant(); try w.apply(); try w.verify()
        let (r, s) = try raw(c)
        // New recipes prepend as a reversed batch; existing entity bytes are verbatim.
        XCTAssertEqual(r.map(\.id), ["r-c", "r-a", "r-old"])
        XCTAssertEqual(r.map(\.position), [0, 1, 2])
        XCTAssertEqual(r.last?.json, seeded.0)
        XCTAssertEqual(s.map(\.id), ["s-old", "s-new"])
        XCTAssertEqual(s.first?.json, seeded.1)
        XCTAssertEqual(try JSONDecoder().decode(RecipeCard.self, from: XCTUnwrap(r.first?.json)).id, "r-c")
    }

    /// A changed existing row keeps its store row under the same @Attribute(.unique)
    /// id through apply and rollback: apply reindexes its position in place (planned
    /// content differs from the stored row), rollback restores the before-image, and
    /// the json bytes stay verbatim throughout.
    func testChangedExistingRowRevertsInPlaceUnderSameUniqueID() throws {
        let c = try container(); let seeded = try seed(c)
        let p = try ArchiveRecipeShoppingParticipant(container: c,
            incomingRecipes: [card("r-new")], incomingShopping: [])
        let w = p.participant(); try w.apply(); try w.verify()
        let during = try raw(c)
        XCTAssertEqual(during.0.map(\.id), ["r-new", "r-old"])
        XCTAssertEqual(during.0.map(\.position), [0, 1])          // r-old reindexed in place
        XCTAssertEqual(during.0.last?.json, seeded.0)              // existing bytes verbatim
        XCTAssertEqual(during.0.last?.createdAt, 111)
        try w.rollback()
        let (r, s) = try raw(c)
        XCTAssertEqual(r.map(\.id), ["r-old"])
        XCTAssertEqual(r.first?.position, 0)                       // before-image restored
        XCTAssertEqual(r.first?.json, seeded.0)
        XCTAssertEqual(r.first?.createdAt, 111)
        XCTAssertEqual(s.map(\.json), [seeded.1])
    }

    /// Existing shopping rows keep their store row under the same @Attribute(.unique)
    /// id: apply updates them in place (never delete+reinsert) and rollback removes
    /// only what it added, leaving existing bytes and positions verbatim.
    func testShoppingExistingRowSurvivesApplyAndRollbackUnderSameUniqueID() throws {
        let c = try container(); let seeded = try seed(c)
        let p = try ArchiveRecipeShoppingParticipant(container: c, incomingRecipes: [],
                                                     incomingShopping: [item("s-new")])
        let w = p.participant(); try w.apply(); try w.verify()
        let during = try raw(c)
        XCTAssertEqual(during.1.map(\.id), ["s-old", "s-new"])
        XCTAssertEqual(during.1.map(\.position), [0, 1])
        XCTAssertEqual(during.1.first?.json, seeded.1) // existing bytes verbatim
        try w.rollback()
        let (r, s) = try raw(c)
        XCTAssertEqual(r.map(\.json), [seeded.0])
        XCTAssertEqual(s.map(\.id), ["s-old"])
        XCTAssertEqual(s.first?.position, 0)
        XCTAssertEqual(s.first?.json, seeded.1)
    }

    func testConcurrentMutationBetweenApplyAndRollbackIsPreservedAndSurfaced() throws {
        let c = try container(); let seeded = try seed(c)
        let p = try ArchiveRecipeShoppingParticipant(container: c, incomingRecipes: [card("r-new")], incomingShopping: [])
        let w = p.participant(); try w.apply()
        // Foreign edit to OUR imported row lands between apply and rollback.
        let ctx = ModelContext(c); ctx.autosaveEnabled = false
        let edited = Data("{\"id\":\"r-new\",\"title\":\"edited elsewhere\"}".utf8)
        try ctx.delete(model: RecipeEntity.self, where: #Predicate { $0.id == "r-new" })
        ctx.insert(RecipeEntity(id: "r-new", createdAt: 999, position: 0, json: edited))
        try ctx.save()
        XCTAssertThrowsError(try w.rollback()) { error in
            guard case ArchiveRestoreFailure.recoveryRequired(_, let failures) = error else {
                return XCTFail("expected recoveryRequired, got \(error)")
            }
            XCTAssertEqual(failures.count, 1)
        }
        let (r, _) = try raw(c)
        XCTAssertEqual(r.first { $0.id == "r-new" }?.json, edited) // foreign edit preserved
        XCTAssertEqual(r.first { $0.id == "r-old" }?.json, seeded.0) // our write reverted
        XCTAssertEqual(r.first { $0.id == "r-old" }?.position, 0)
    }

    func testDefaultsConcurrentWriteBetweenApplyAndRollbackIsPreserved() throws {
        let d = try suite()
        let p = try ArchiveDefaultsParticipant(defaults: d, settings: AppSettings(), timerPrefs: TimerPrefs())
        let w = p.participant(); try w.apply()
        let foreign = Data("foreign".utf8)
        d.set(foreign, forKey: ArchiveDefaultsParticipant.settingsKey)
        XCTAssertThrowsError(try w.rollback()) { error in
            guard case ArchiveRestoreFailure.recoveryRequired(_, let failures) = error else {
                return XCTFail("expected recoveryRequired, got \(error)")
            }
            XCTAssertEqual(failures.count, 1)
        }
        XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.settingsKey), foreign) // preserved
        XCTAssertNil(d.data(forKey: ArchiveDefaultsParticipant.timerKey))               // our write reverted
    }

    private func suite() throws -> UserDefaults {
        let name = "ArchiveDefaults-" + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testDefaultsEveryBoundaryRestoresExactRawBytesAndAbsentKeys() throws {
        for boundary in ArchiveDefaultsParticipant.Boundary.allCases {
            let d = try suite()
            let oldSettings = Data([0x7B, 0x00, 0x7D]) // non-canonical: must survive verbatim
            d.set(oldSettings, forKey: ArchiveDefaultsParticipant.settingsKey)
            d.set(Data("sync-meta".utf8), forKey: ArchiveDefaultsParticipant.syncMetaKey)
            var settings = AppSettings(); settings.units = .imperial
            let p = try ArchiveDefaultsParticipant(defaults: d, settings: settings, timerPrefs: TimerPrefs(),
                checkpoint: { if $0 == boundary { throw Injected.failure } })
            XCTAssertThrowsError(try { let w = p.participant(); try w.apply(); try w.verify() }())
            try p.participant().rollback()
            XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.settingsKey), oldSettings, "\(boundary)")
            XCTAssertNil(d.data(forKey: ArchiveDefaultsParticipant.timerKey), "\(boundary)")
            XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.syncMetaKey), Data("sync-meta".utf8), "\(boundary)")
        }
    }

    func testDefaultsChangedSourceRefusesAndPreservesNewValue() throws {
        let d = try suite()
        let p = try ArchiveDefaultsParticipant(defaults: d, settings: AppSettings(), timerPrefs: TimerPrefs())
        let changed = Data("changed".utf8)
        d.set(changed, forKey: ArchiveDefaultsParticipant.syncMetaKey)
        XCTAssertThrowsError(try p.participant().apply())
        try p.participant().rollback()
        XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.syncMetaKey), changed)
        XCTAssertNil(d.data(forKey: ArchiveDefaultsParticipant.settingsKey))
    }

    func testRecipeValidationFailureStopsBeforeUndoOrSaveForAnyErrorType() throws {
        let c = try container(); _ = try seed(c)
        var deny = false
        var validations = 0
        var saves = 0
        let p = try ArchiveRecipeShoppingParticipant(container: c,
            incomingRecipes: [card("r-new")], incomingShopping: [item("s-new")],
            save: { context in saves += 1; try context.save() },
            validate: {
                validations += 1
                if deny { throw Injected.failure }
            })
        let w = p.participant(); try w.apply()
        let beforeUndo = try raw(c)
        validations = 0; deny = true
        XCTAssertThrowsError(try w.rollback()) { error in
            guard case ArchiveRestoreFailure.recoveryRequired = error else {
                return XCTFail("must surface recoveryRequired, got \(error)")
            }
        }
        XCTAssertEqual(validations, 1, "no later row/component after failed validation")
        XCTAssertEqual(saves, 1, "no undo save after lost ownership")
        let afterUndo = try raw(c)
        XCTAssertEqual(afterUndo.0, beforeUndo.0)
        XCTAssertEqual(afterUndo.1, beforeUndo.1)
    }

    func testRecipeRevalidatesBeforeCompensatingSave() throws {
        let c = try container(); _ = try seed(c)
        var denyAtSave = false
        var checks = 0
        var saves = 0
        let p = try ArchiveRecipeShoppingParticipant(container: c,
            incomingRecipes: [card("r-new")], incomingShopping: [],
            save: { context in saves += 1; try context.save() },
            validate: {
                checks += 1
                // r-new deletion, r-old deletion and insertion, unchanged
                // s-old check, then the final validation at the durable save.
                if denyAtSave && checks == 5 { throw Injected.failure }
            })
        let w = p.participant(); try w.apply()
        let beforeUndo = try raw(c)
        checks = 0; denyAtSave = true
        XCTAssertThrowsError(try w.rollback())
        XCTAssertEqual(checks, 5)
        XCTAssertEqual(saves, 1)
        let afterUndo = try raw(c)
        XCTAssertEqual(afterUndo.0, beforeUndo.0)
        XCTAssertEqual(afterUndo.1, beforeUndo.1)
    }

    func testValidationFailureBetweenUndoDeleteAndInsertPreventsSave() throws {
        let c = try container(); _ = try seed(c)
        var undo = false
        var checks = 0
        var saves = 0
        let p = try ArchiveRecipeShoppingParticipant(container: c,
            incomingRecipes: [card("r-new")], incomingShopping: [],
            save: { context in saves += 1; try context.save() },
            validate: {
                checks += 1
                if undo && checks == 3 { throw Injected.failure }
            })
        let w = p.participant(); try w.apply()
        let beforeUndo = try raw(c)
        checks = 0; undo = true
        XCTAssertThrowsError(try w.rollback())
        XCTAssertEqual(checks, 3)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(try raw(c).0, beforeUndo.0)
        XCTAssertEqual(try raw(c).1, beforeUndo.1)
    }

    func testDefaultsValidationFailureStopsBeforeAnyKeyUndo() throws {
        let d = try suite()
        var deny = false
        var checks = 0
        let p = try ArchiveDefaultsParticipant(defaults: d, settings: AppSettings(), timerPrefs: TimerPrefs(),
            validate: { checks += 1; if deny { throw Injected.failure } })
        let w = p.participant(); try w.apply()
        let settingsAfter = d.data(forKey: ArchiveDefaultsParticipant.settingsKey)
        let timerAfter = d.data(forKey: ArchiveDefaultsParticipant.timerKey)
        deny = true; checks = 0
        XCTAssertThrowsError(try w.rollback()) { error in
            guard case ArchiveRestoreFailure.recoveryRequired = error else {
                return XCTFail("must surface recoveryRequired, got \(error)")
            }
        }
        XCTAssertEqual(checks, 1, "timer must not be attempted after settings loses ownership")
        XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.settingsKey), settingsAfter)
        XCTAssertEqual(d.data(forKey: ArchiveDefaultsParticipant.timerKey), timerAfter)
    }

    func testCompositeRollsBackEveryComponentIndependently() throws {
        let d = try suite()
        let defaultsParticipant = try ArchiveDefaultsParticipant(defaults: d, settings: AppSettings(), timerPrefs: TimerPrefs())
        var secondRolledBack = false
        let failing = ArchiveRestoreParticipant(apply: {}, verify: { throw Injected.failure },
                                                rollback: { secondRolledBack = true; throw Injected.failure })
        let composite = ArchiveOuterComposite(components: [defaultsParticipant.participant(), failing]).participant()
        try composite.apply()
        XCTAssertThrowsError(try composite.verify())
        XCTAssertThrowsError(try composite.rollback()) { error in
            guard case ArchiveRestoreFailure.recoveryRequired(_, let failures) = error else {
                return XCTFail("expected recoveryRequired, got \(error)")
            }
            XCTAssertEqual(failures.count, 1)
        }
        XCTAssertTrue(secondRolledBack)
        XCTAssertNil(d.data(forKey: ArchiveDefaultsParticipant.settingsKey))
        XCTAssertNil(d.data(forKey: ArchiveDefaultsParticipant.timerKey))
    }
}
