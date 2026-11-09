import XCTest
import SwiftData
@testable import Ate

@MainActor
final class JournalArchiveRestoreTests: XCTestCase {
    enum Injected: Error { case failure, intentFailure }

    private func reflection() -> JournalArchiveEntry {
        JournalArchiveEntry(id: "r-1", createdAt: Date(timeIntervalSince1970: 1234),
            prompt: "Dinner?", text: "Dinner", stateRaw: "future-state", recipeIDs: ["recipe-1"],
            journalingSuggestionTitle: "Dinner", momentDate: Date(timeIntervalSince1970: 1200),
            sourceRaw: "future-source", locationName: "Home", latitude: -26.2, longitude: 28.0,
            mediaFileNames: [], editedAt: Date(timeIntervalSince1970: 1250), kindRaw: "reflection",
            dayKey: nil, recipeSnapshotsRaw: "{undecodable-future}", meal: nil)
    }

    private var noOuter: ArchiveRestoreParticipant {
        ArchiveRestoreParticipant(apply: {}, verify: {}, rollback: {})
    }

    func testEveryCommitBoundaryCompensatesInsertedRowsAndOuterState() throws {
        for boundary in ArchiveRestoreBoundary.allCases {
            let journal = JournalStore(inMemory: true)
            let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
            let media = MemoryMedia()
            var intentCalls = 0
            var outerValue = "before"
            let outer = ArchiveRestoreParticipant(apply: { outerValue = "after" }, verify: {},
                                                  rollback: { outerValue = "before" })
            XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: media,
                outer: outer, beforeCompensation: { intentCalls += 1 }, checkpoint: { if $0 == boundary { throw Injected.failure } }))
            XCTAssertEqual(intentCalls, 1, "\(boundary)")
            XCTAssertEqual(outerValue, "before", "\(boundary)")
            XCTAssertTrue(media.staged.isEmpty, "\(boundary)")
            XCTAssertTrue(media.published.isEmpty, "\(boundary)")
            let context = ModelContext(try XCTUnwrap(journal.container))
            XCTAssertTrue(try context.fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty, "\(boundary)")
            XCTAssertTrue(try context.fetch(FetchDescriptor<JournalMealPayload>()).isEmpty, "\(boundary)")
        }
    }

    func testRestoreRawFieldsRoundTripAndRepeatIsNoOp() async throws {
        let journal = JournalStore(inMemory: true)
        let archive = JournalArchive(entries: [reflection()], media: [:])
        let plan = try JournalArchiveRestore.prepare(archive, journal: journal)
        XCTAssertEqual(try JournalArchiveRestore.execute(plan, journal: journal, media: MemoryMedia(), outer: noOuter, beforeCompensation: {}), 1)
        let actual = try await JournalArchiveCapture.captureWithMedia(journal: journal)
        XCTAssertEqual(actual.entries, archive.entries)
        let repeatPlan = try JournalArchiveRestore.prepare(archive, journal: journal)
        XCTAssertEqual(repeatPlan.skippedExisting, 1)
        XCTAssertEqual(try JournalArchiveRestore.execute(repeatPlan, journal: journal, media: MemoryMedia(), outer: noOuter, beforeCompensation: {}), 0)
    }

    func testExistingIdentityWinsWithoutOverwritingNewerText() throws {
        let journal = JournalStore(inMemory: true)
        let original = JournalArchive(entries: [reflection()], media: [:])
        let first = try JournalArchiveRestore.prepare(original, journal: journal)
        _ = try JournalArchiveRestore.execute(first, journal: journal, media: MemoryMedia(), outer: noOuter, beforeCompensation: {})
        var older = reflection(); older.text = "older backup"
        let next = try JournalArchiveRestore.prepare(JournalArchive(entries: [older], media: [:]), journal: journal)
        XCTAssertTrue(next.archive.entries.isEmpty)
        let row = try XCTUnwrap(ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>()).first)
        XCTAssertEqual(row.text, reflection().text)
    }

    func testPartialOuterWriteIsCompensatedWhenApplyThrows() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        var outerValue = "before"
        let outer = ArchiveRestoreParticipant(apply: { outerValue = "partial"; throw Injected.failure },
                                              verify: {}, rollback: { outerValue = "before" })
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: MemoryMedia(), outer: outer, beforeCompensation: {}))
        XCTAssertEqual(outerValue, "before")
    }

    func testSaveThenThrowStillRemovesDurableInsertions() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        var saves = 0
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: MemoryMedia(), outer: noOuter, beforeCompensation: {},
            save: { context in
                try context.save(); saves += 1
                if saves == 1 { throw Injected.failure }
            }))
        XCTAssertEqual(saves, 2)
        XCTAssertTrue(try ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
    }

    func testFailedCompensationIsVisibleAndOtherCompensationsStillRun() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        let media = MemoryMedia()
        let outer = ArchiveRestoreParticipant(apply: {}, verify: { throw Injected.failure },
                                              rollback: { throw Injected.failure })
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: media, outer: outer, beforeCompensation: {})) { error in
            guard case ArchiveRestoreFailure.recoveryRequired(_, let failures) = error else {
                return XCTFail("must expose recoveryRequired, got \(error)")
            }
            XCTAssertEqual(failures.count, 1)
        }
        XCTAssertTrue(media.rolledBack)
        XCTAssertTrue(try ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
    }

    func testFailedIntentPreventsAllCompensationAndRetainsPartialState() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        let media = MemoryMedia()
        var outerValue = "before"
        var outerUndoCount = 0
        var saveCount = 0
        var intentCount = 0
        let outer = ArchiveRestoreParticipant(apply: { outerValue = "after" },
            verify: { throw Injected.failure },
            rollback: { outerUndoCount += 1; outerValue = "before" })
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: media,
            outer: outer, beforeCompensation: {
                intentCount += 1
                throw Injected.intentFailure
            }, save: { context in saveCount += 1; try context.save() })) { error in
                guard case ArchiveRestoreFailure.recoveryRequired(let original, let failures) = error else {
                    return XCTFail("must retain recoveryRequired, got \(error)")
                }
                XCTAssertEqual(original, String(describing: Injected.failure))
                XCTAssertEqual(failures, ["compensation intent: \(Injected.intentFailure)"])
            }
        XCTAssertEqual(intentCount, 1)
        XCTAssertEqual(outerUndoCount, 0)
        XCTAssertEqual(saveCount, 1, "no compensating save after intent failure")
        XCTAssertEqual(outerValue, "after")
        XCTAssertFalse(media.rolledBack)
        let rows = try ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.map(\.id), [reflection().id], "retain durable rows for recovery")
    }

    func testDurableIntentPrecedesEveryUndoWhenFinishFails() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        let media = MemoryMedia()
        media.failFinish = true
        var intentRecorded = false
        var saves = 0
        var outerUndone = false
        let outer = ArchiveRestoreParticipant(apply: {}, verify: {}, rollback: {
            XCTAssertTrue(intentRecorded)
            outerUndone = true
        })
        media.beforeRollback = { XCTAssertTrue(intentRecorded) }
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: media,
            outer: outer, beforeCompensation: { intentRecorded = true },
            save: { context in
                saves += 1
                if saves > 1 { XCTAssertTrue(intentRecorded) }
                try context.save()
            })) { error in
                guard case Injected.failure = error else { return XCTFail("wrong original error: \(error)") }
            }
        XCTAssertTrue(intentRecorded)
        XCTAssertTrue(outerUndone)
        XCTAssertTrue(media.rolledBack)
        XCTAssertEqual(saves, 2)
        XCTAssertTrue(try ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
    }

    func testFailedIntentAfterFinishFailureDoesNotUndoCommittedState() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        let media = MemoryMedia()
        media.failFinish = true
        var outerUndone = false
        let outer = ArchiveRestoreParticipant(apply: {}, verify: {}, rollback: { outerUndone = true })
        XCTAssertThrowsError(try JournalArchiveRestore.execute(plan, journal: journal, media: media,
            outer: outer, beforeCompensation: { throw Injected.intentFailure })) { error in
                guard case ArchiveRestoreFailure.recoveryRequired(_, let failures) = error else {
                    return XCTFail("expected recoveryRequired, got \(error)")
                }
                XCTAssertEqual(failures, ["compensation intent: \(Injected.intentFailure)"])
            }
        XCTAssertFalse(outerUndone)
        XCTAssertFalse(media.rolledBack)
        XCTAssertEqual(try ModelContext(try XCTUnwrap(journal.container)).fetch(FetchDescriptor<Ate.JournalEntry>()).count, 1)
    }

    func testSuccessfulRestoreDoesNotRequestCompensationIntent() throws {
        let journal = JournalStore(inMemory: true)
        let plan = try JournalArchiveRestore.prepare(JournalArchive(entries: [reflection()], media: [:]), journal: journal)
        var intentCalls = 0
        XCTAssertEqual(try JournalArchiveRestore.execute(plan, journal: journal, media: MemoryMedia(),
            outer: noOuter, beforeCompensation: { intentCalls += 1 }), 1)
        XCTAssertEqual(intentCalls, 0)
    }

    func testMealPayloadDayAndProvenanceRoundTripWithoutBalancedReading() async throws {
        let journal = JournalStore(inMemory: true)
        let meal = NutritionDiaryEntry(foodName: "Pap", date: Date(timeIntervalSince1970: 1234), meal: .dinner,
            quantity: 1, quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
            sourceIdentifier: "source-id", verificationNote: "User supplied", nutrientsPerServing:
                NutritionSnapshot(energyKcal: nil, proteinGrams: 5, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
            dayKey: "2026-11-04")
        var row = reflection()
        row.id = meal.id.uuidString; row.createdAt = meal.date; row.kindRaw = "meal"
        row.stateRaw = ""; row.text = ""; row.dayKey = meal.dayKey; row.meal = meal
        let archive = JournalArchive(entries: [row], media: [:])
        let plan = try JournalArchiveRestore.prepare(archive, journal: journal)
        _ = try JournalArchiveRestore.execute(plan, journal: journal, media: MemoryMedia(), outer: noOuter, beforeCompensation: {})
        XCTAssertEqual(try FoodJournalStore(container: journal.container).readMeals(), [meal])
        let captured = try await JournalArchiveCapture.captureWithMedia(journal: journal)
        XCTAssertEqual(captured.entries, [row])
        row.dayKey = "2026-02-30"; row.meal?.dayKey = "2026-02-30"
        XCTAssertThrowsError(try JournalArchiveRestore.prepare(JournalArchive(entries: [row], media: [:]), journal: journal))
    }
}

@MainActor
private final class MemoryMedia: ArchiveMediaTransaction {
    var staged: [String: Data] = [:]
    var published: [String: Data] = [:]
    var rolledBack = false
    var failFinish = false
    var beforeRollback: () -> Void = {}
    func stage(_ media: [String: Data]) throws { staged = media }
    func publish() throws { published = staged }
    func verify() throws {}
    func rollback() throws { beforeRollback(); staged = [:]; published = [:]; rolledBack = true }
    func finish() throws {
        if failFinish { throw JournalArchiveRestoreTests.Injected.failure }
        staged = [:]
    }
}
