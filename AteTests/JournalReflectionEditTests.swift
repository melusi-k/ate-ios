import XCTest
import SwiftData
@testable import Ate

@MainActor
final class JournalReflectionEditTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testFailedEditKeepsCommittedReaderAndUnrelatedPendingWorkThenRetryCommits() throws {
        enum Injected: Error { case save }
        let c = try container()
        let healthy = JournalStore(container: c, openState: .ok)
        let id = try healthy.saveManual(text: "Original")
        let reader = try XCTUnwrap(healthy.readEntry(id))
        let originalDate = reader.createdAt
        let unrelated = Ate.JournalEntry(prompt: "", text: "Unrelated pending", state: nil)
        c.mainContext.insert(unrelated)
        let failing = JournalStore(container: c, openState: .ok,
                                   writeReflectionContext: { _ in throw Injected.save })
        XCTAssertFalse(failing.update(reader, text: "Retained edit draft"))
        XCTAssertEqual(reader.text, "Original"); XCTAssertNil(reader.editedAt)
        XCTAssertEqual(try healthy.readEntry(id)?.text, "Original")
        XCTAssertTrue(c.mainContext.hasChanges)
        XCTAssertEqual(unrelated.text, "Unrelated pending")
        XCTAssertTrue(healthy.update(reader, text: "  Retained edit draft  "))
        XCTAssertEqual(reader.text, "Retained edit draft")
        XCTAssertNotNil(reader.editedAt)
        XCTAssertEqual(try healthy.readEntry(id)?.text, "Retained edit draft")
        XCTAssertEqual(reader.createdAt, originalDate)
        XCTAssertEqual(try healthy.readEntries().map(\.id), [id])
        XCTAssertTrue(c.mainContext.hasChanges)
    }

    func testUnavailableEmptyMissingAndNonReflectionEditsReturnFalse() throws {
        let c = try container()
        let healthy = JournalStore(container: c, openState: .ok)
        let id = try healthy.saveManual(text: "Original")
        let row = try XCTUnwrap(healthy.readEntry(id))
        XCTAssertFalse(JournalStore(container: c, openState: .unavailable(error: nil)).update(row, text: "No"))
        XCTAssertFalse(healthy.update(row, text: " \n"))
        XCTAssertFalse(healthy.update(Ate.JournalEntry(prompt: "", text: "Unsaved", state: nil), text: "No"))
        row.kindRaw = "future-kind"
        XCTAssertFalse(healthy.update(row, text: "No"))
        XCTAssertEqual(try healthy.readEntry(id)?.text, "Original")
    }
}
