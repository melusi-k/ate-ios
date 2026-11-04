import XCTest
import CryptoKit
import SwiftData
@testable import Ate

final class JournalArchiveTests: XCTestCase {
    private func reflection() -> JournalArchiveEntry {
        JournalArchiveEntry(id: "reflection-1", createdAt: Date(timeIntervalSince1970: 1234), prompt: "Dinner?",
                            text: "Family dinner", stateRaw: "future-state", recipeIDs: ["recipe-1"],
                            journalingSuggestionTitle: "Dinner", momentDate: Date(timeIntervalSince1970: 1200),
                            sourceRaw: "future-source", locationName: "Home", latitude: -26.2, longitude: 28.0,
                            mediaFileNames: ["photo.jpg"], editedAt: Date(timeIntervalSince1970: 1250),
                            kindRaw: "reflection", dayKey: nil, recipeSnapshotsRaw: "{unreadable-future-version}", meal: nil)
    }
    func testRawFieldsAndActualMediaBytesRoundTripWithoutNormalization() throws {
        var a = JournalArchive(entries: [reflection()], media: ["photo.jpg": Data([0, 1, 2, 255])])
        a.mediaSHA256["photo.jpg"] = SHA256.hash(data: Data([0, 1, 2, 255])).map { String(format: "%02x", $0) }.joined()
        try JournalArchiveValidation.validate(a)
        let b = try JSONDecoder().decode(JournalArchive.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(a, b)
        XCTAssertEqual(b.entries[0].stateRaw, "future-state")
        XCTAssertEqual(b.entries[0].sourceRaw, "future-source")
        XCTAssertEqual(b.entries[0].recipeSnapshotsRaw, "{unreadable-future-version}")
        XCTAssertEqual(b.media["photo.jpg"], Data([0, 1, 2, 255]))
    }
    func testMissingMediaAndUnsafeBasenamesFailValidation() throws {
        XCTAssertThrowsError(try JournalArchiveValidation.validate(JournalArchive(entries: [reflection()], media: [:])))
        for name in ["../photo.jpg", "/absolute", "..", "a\\b", "a\0b", ""] {
            XCTAssertFalse(JournalArchiveValidation.safeMediaName(name))
        }
    }
    func testDuplicateIdentityAndMediaLimitFailBeforeRestore() throws {
        let row = reflection()
        XCTAssertThrowsError(try JournalArchiveValidation.validate(JournalArchive(entries: [row, row], media: ["photo.jpg": Data()])))
        XCTAssertThrowsError(try JournalArchiveValidation.validate(JournalArchive(entries: [row], media: ["photo.jpg": Data([1,2])]), maximumMediaBytes: 1))
    }
    func testMealKindCannotOmitStructuredPayload() throws {
        var row = reflection()
        row.kindRaw = "meal"
        XCTAssertThrowsError(try JournalArchiveValidation.validate(JournalArchive(entries: [row], media: ["photo.jpg": Data()])))
    }
    func testCoordinatesAndFutureArchiveVersionAreRejected() throws {
        var row = reflection()
        row.latitude = 91
        XCTAssertThrowsError(try JournalArchiveValidation.validate(JournalArchive(entries: [row], media: ["photo.jpg": Data()])))
        var archive = JournalArchive(entries: [], media: [:])
        archive.version = 999
        XCTAssertThrowsError(try JournalArchiveValidation.validate(archive))
    }
    @MainActor
    func testCaptureRejectsEveryIncompleteOpenState() throws {
        for state in [JournalOpenState.recovered(backupName: "backup"), .inMemoryFallback(error: "test"), .unavailable(error: "test")] {
            XCTAssertThrowsError(try JournalArchiveCapture.requireCompleteStore(state)) {
                XCTAssertEqual($0 as? JournalArchiveError, .unavailable)
            }
        }
        XCTAssertNoThrow(try JournalArchiveCapture.requireCompleteStore(.ok))
    }
    @MainActor
    func testCaptureReadsMediaAndRawReflectionFromIsolatedStore() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data([1, 2, 3])
        try data.write(to: dir.appendingPathComponent("photo.jpg"))
        let journal = JournalStore(inMemory: true)
        let context = try XCTUnwrap(journal.container?.mainContext)
        let row = Ate.JournalEntry(id: "reflection-1", prompt: "Dinner?", text: "Dinner", state: .balanced)
        row.stateRaw = "future-state"
        row.recipeSnapshotsRaw = "unreadable-but-preserved"
        row.mediaFileNames = ["photo.jpg"]
        context.insert(row)
        try context.save()
        let result = try await JournalArchiveCapture.captureWithMedia(journal: journal, mediaDirectory: dir)
        XCTAssertEqual(result.entries.first?.stateRaw, "future-state")
        XCTAssertEqual(result.entries.first?.recipeSnapshotsRaw, "unreadable-but-preserved")
        XCTAssertEqual(result.media["photo.jpg"], data)
        XCTAssertNotNil(result.mediaSHA256["photo.jpg"])
        XCTAssertThrowsError(try JournalArchiveMedia.load(JournalArchive(entries: [reflection()], media: [:]), directory: dir, maximumBytes: 1))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("photo.jpg"))
        do { _ = try await JournalArchiveCapture.captureWithMedia(journal: journal, mediaDirectory: dir); XCTFail("missing media must fail") }
        catch { XCTAssertEqual(error as? JournalArchiveError, .missingMedia) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("photo.jpg"), withDestinationURL: dir.appendingPathComponent("target.jpg"))
        XCTAssertThrowsError(try JournalArchiveMedia.load(JournalArchive(entries: [reflection()], media: [:]), directory: dir, maximumBytes: 100))
    }
    func testMediaHashMismatchFailsValidation() throws {
        var archive = JournalArchive(entries: [reflection()], media: ["photo.jpg": Data([1])])
        archive.mediaSHA256["photo.jpg"] = "wrong"
        XCTAssertThrowsError(try JournalArchiveValidation.validate(archive)) {
            XCTAssertEqual($0 as? JournalArchiveError, .mediaIntegrity)
        }
    }

    @MainActor
    func testCaptureRefusesOrphanMealPayload() async throws {
        let journal = JournalStore(inMemory: true)
        let context = try XCTUnwrap(journal.container?.mainContext)
        context.insert(JournalMealPayload(entryID: UUID().uuidString, meal: .dinner, foodName: "Pap", quantity: 1,
                                          quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
                                          nutrients: NutritionSnapshot(energyKcal: nil, proteinGrams: nil,
                                                                       carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)))
        try context.save()
        do { _ = try await JournalArchiveCapture.captureWithMedia(journal: journal); XCTFail("orphan must fail") }
        catch { XCTAssertEqual(error as? FoodJournalStoreError, .unreadableStore) }
    }

}
