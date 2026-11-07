import XCTest
import SwiftData
@testable import Ate

/// #245 phase 5 storage groundwork: recipe snapshot codec, the guarded write helper and the additive
/// `recipeSnapshotsRaw` column. The test target also declares a legacy top-level `JournalEntry` fixture
/// (LegacyJournalStoreUpgradeTests.swift) that shadows the app type target-wide, so the app type is always
/// written `Ate.JournalEntry` here and this file declares no `JournalEntry` of its own.
@MainActor
final class JournalRecipeSnapshotTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    private let cooked = JournalRecipeSnapshot(recipeID: "r1", title: "Mogodu \u{2013} Sunday", cookedDayKey: "2026-11-01")
    private let suggested = JournalRecipeSnapshot(recipeID: "r2", title: "Lentil soup", cookedDayKey: nil)
    private let future = #"{"version":2,"snapshots":[{"recipeID":"r1","title":"From a newer build"}]}"#
    private let garbage = "not json {"

    private func openStore(_ name: String = "journal.store") throws -> ModelContainer {
        try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                           configurations: ModelConfiguration(url: dir.appendingPathComponent(name)))
    }

    // MARK: codec

    func testCodecRoundTripKeepsEveryField() throws {
        let raw = try JournalRecipeSnapshotCodec.encode([cooked, suggested])
        XCTAssertNotNil(raw)
        XCTAssertEqual(JournalRecipeSnapshotCodec.decode(raw), .snapshots([cooked, suggested]))
    }

    func testEmptyListEncodesToNilAndNilOrEmptyDecodesToNone() throws {
        XCTAssertNil(try JournalRecipeSnapshotCodec.encode([]))
        XCTAssertEqual(JournalRecipeSnapshotCodec.decode(nil), .none)
        XCTAssertEqual(JournalRecipeSnapshotCodec.decode(""), .none)
    }

    func testUnreadableOrUnknownVersionIsReportedWithDetailNotThrown() {
        guard case .undecodable(let garbageReason) = JournalRecipeSnapshotCodec.decode(garbage) else {
            return XCTFail("garbage must be undecodable")
        }
        XCTAssertTrue(garbageReason.hasPrefix("no readable version:"), garbageReason)
        XCTAssertGreaterThan(garbageReason.count, "no readable version:".count, "carries the DecodingError detail")
        guard case .undecodable(let futureReason) = JournalRecipeSnapshotCodec.decode(future) else {
            return XCTFail("a newer version must be undecodable, not read as v1")
        }
        XCTAssertTrue(futureReason.contains("version 2"), futureReason)
        guard case .undecodable(let shapeReason) = JournalRecipeSnapshotCodec.decode(#"{"version":1,"snapshots":"oops"}"#) else {
            return XCTFail("a v1 payload with the wrong shape must be undecodable")
        }
        XCTAssertTrue(shapeReason.contains("does not match its shape:"), shapeReason)
        XCTAssertGreaterThan(shapeReason.count, 60, "carries the DecodingError detail")
    }

    // MARK: guarded write helper

    func testSetStoresValidV1AndReplacesAnExistingValidV1() throws {
        let entry = Ate.JournalEntry(prompt: "", text: "Cooked it", state: .balanced, recipeIDs: ["r1"])
        XCTAssertTrue(try entry.setRecipeSnapshots([cooked]))
        XCTAssertEqual(entry.recipeSnapshotDecoding, .snapshots([cooked]))
        XCTAssertTrue(try entry.setRecipeSnapshots([cooked, suggested]))
        XCTAssertEqual(entry.recipeSnapshotDecoding, .snapshots([cooked, suggested]), "valid v1 is replaced")
    }

    func testEmptyInputIsANoOpOnEveryStoredState() throws {
        let fresh = Ate.JournalEntry(prompt: "", text: "a", state: .balanced)
        XCTAssertFalse(try fresh.setRecipeSnapshots([]))
        XCTAssertNil(fresh.recipeSnapshotsRaw)

        let valid = Ate.JournalEntry(prompt: "", text: "b", state: .balanced)
        try valid.setRecipeSnapshots([cooked])
        let before = valid.recipeSnapshotsRaw
        XCTAssertFalse(try valid.setRecipeSnapshots([]))
        XCTAssertEqual(valid.recipeSnapshotsRaw, before, "empty input never clears valid snapshots")

        let damaged = Ate.JournalEntry(prompt: "", text: "c", state: .balanced)
        damaged.recipeSnapshotsRaw = future
        XCTAssertFalse(try damaged.setRecipeSnapshots([]), "empty input is a no-op, not a refusal")
        XCTAssertEqual(damaged.recipeSnapshotsRaw, future)
    }

    func testUndecodablePayloadsAreRefusedAndStayByteIdentical() throws {
        for raw in [future, garbage, #"{"version":1,"snapshots":"oops"}"#] {
            let entry = Ate.JournalEntry(prompt: "", text: "d", state: .balanced, recipeIDs: ["r1", "r2"])
            entry.recipeSnapshotsRaw = raw
            XCTAssertThrowsError(try entry.setRecipeSnapshots([cooked])) { error in
                guard case JournalRecipeSnapshotWriteError.existingPayloadUndecodable = error else {
                    return XCTFail("expected existingPayloadUndecodable, got \(error)")
                }
            }
            XCTAssertEqual(entry.recipeSnapshotsRaw, raw, "refused write leaves the raw payload byte-identical")
            XCTAssertEqual(Array(entry.recipeSnapshotsRaw?.utf8 ?? "".utf8), Array(raw.utf8))
            XCTAssertEqual(entry.recipeIDs, ["r1", "r2"])
        }
    }

    // MARK: persistence (real on-disk stores, fresh containers, no shared identity map)

    func testUndecodablePayloadSurvivesReopenAndReadingDoesNotWrite() throws {
        var id = ""
        do {
            let container = try openStore()
            let entry = Ate.JournalEntry(prompt: "", text: "Cooked it", state: .balanced, recipeIDs: ["r1", "r2"])
            entry.recipeSnapshotsRaw = future
            id = entry.id
            container.mainContext.insert(entry)
            try container.mainContext.save()
        }
        do {
            let reopened = try openStore()
            let ctx = reopened.mainContext
            let rows = try ctx.fetch(FetchDescriptor<Ate.JournalEntry>())
            XCTAssertEqual(rows.count, 1, "the reopen must actually find the row")
            let row = try XCTUnwrap(rows.first { $0.id == id })
            guard case .undecodable = row.recipeSnapshotDecoding else { return XCTFail("future version must not decode") }
            XCTAssertEqual(row.recipeSnapshotsRaw, future)
            XCTAssertEqual(row.recipeIDs, ["r1", "r2"], "links are never lost with the snapshot")
            XCTAssertNil(row.editedAt, "decoding does not write")
            XCTAssertFalse(ctx.hasChanges, "decoding leaves the context clean")
            XCTAssertThrowsError(try row.setRecipeSnapshots([cooked]))
            XCTAssertFalse(ctx.hasChanges, "a refused write leaves the context clean")
        }
        let third = try openStore()
        let again = try XCTUnwrap(try third.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>()).first { $0.id == id })
        XCTAssertEqual(again.recipeSnapshotsRaw, future, "still byte-identical after a refused write and another reopen")
    }

    func testSnapshotsWrittenThroughTheHelperSurviveReopen() throws {
        var id = ""
        do {
            let container = try openStore()
            let entry = Ate.JournalEntry(prompt: "", text: "Pap and mogodu", state: .balanced, recipeIDs: ["r1", "r2"])
            try entry.setRecipeSnapshots([cooked, suggested])
            id = entry.id
            container.mainContext.insert(entry)
            try container.mainContext.save()
        }
        let reopened = try openStore()
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first { $0.id == id })
        XCTAssertEqual(row.recipeIDs, ["r1", "r2"])
        XCTAssertEqual(row.recipeSnapshotDecoding, .snapshots([cooked, suggested]))
    }

    func testRowWithoutSnapshotsDecodesToNone() {
        let entry = Ate.JournalEntry(prompt: "", text: "Plain note", state: .balanced, recipeIDs: ["r1"])
        XCTAssertNil(entry.recipeSnapshotsRaw)
        XCTAssertEqual(entry.recipeSnapshotDecoding, .none)
    }
}
