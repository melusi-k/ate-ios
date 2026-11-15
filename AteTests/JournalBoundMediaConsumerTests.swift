import XCTest
import SwiftData
@testable import Ate

@MainActor
final class JournalBoundMediaConsumerTests: XCTestCase {
    private func fixture(_ run: (JournalStore, Ate.JournalEntry, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoundMedia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let journal = JournalStore(container: container, openState: .ok, mediaDirectory: root)
        let row = Ate.JournalEntry(prompt: "", text: "Owned photo", state: nil)
        row.mediaFileNames = ["owned.jpg"]
        let writer = ModelContext(container)
        writer.insert(row)
        try writer.save()
        try Data([7, 8, 9]).write(to: root.appendingPathComponent("owned.jpg"))
        try await run(journal, row, root)
    }
    func testDefaultArchiveCaptureLoadsTheSuppliedJournalsMediaNotGlobalDirectory() async throws {
        try await fixture { journal, row, _ in
            let archive = try await JournalArchiveCapture.captureWithMedia(journal: journal)
            XCTAssertEqual(archive.entries.map(\.id), [row.id])
            XCTAssertEqual(archive.media["owned.jpg"], Data([7, 8, 9]))
        }
    }
    func testIntentEntityUsesTheSameJournalMediaLocationAsItsRecord() async throws {
        try await fixture { journal, row, root in
            let entity = AteJournalEntryEntity(row, journal: journal)
            XCTAssertEqual(entity.id, row.id)
            XCTAssertEqual(entity.mediaItems.count, 1)
            XCTAssertEqual(entity.mediaItems.first?.data, Data([7, 8, 9]))
            XCTAssertEqual(journal.boundMediaURL("owned.jpg"), root.appendingPathComponent("owned.jpg"))
        }
    }
    func testMissingOwnedMediaFailsRatherThanExportingAnEmptyAttachmentSet() async throws {
        try await fixture { journal, _, root in
            try FileManager.default.removeItem(at: root.appendingPathComponent("owned.jpg"))
            do {
                _ = try await JournalArchiveCapture.captureWithMedia(journal: journal)
                XCTFail("Missing owned media must remain a visible export failure")
            } catch { XCTAssertEqual(error as? JournalArchiveError, .missingMedia) }
        }
    }
}
