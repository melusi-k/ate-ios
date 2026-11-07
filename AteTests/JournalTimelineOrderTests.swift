import XCTest
import SwiftData
@testable import Ate

@MainActor
final class JournalTimelineOrderTests: XCTestCase {
    func testEntriesRemainNewestFirstWhenInsertedOutOfOrder() throws {
        let journal = JournalStore(inMemory: true)
        let context = try XCTUnwrap(journal.container?.mainContext)
        for (id, instant) in [("middle", 200.0), ("oldest", 100.0), ("newest", 300.0)] {
            context.insert(Ate.JournalEntry(id: id, createdAt: Date(timeIntervalSince1970: instant),
                prompt: "Context", text: id, state: .balanced))
        }
        try context.save()
        let rows = journal.entries()
        XCTAssertEqual(rows.map(\.id), ["newest", "middle", "oldest"])
        XCTAssertEqual(rows.map(\.createdAt), [300.0, 200.0, 100.0].map { Date(timeIntervalSince1970: $0) })
        XCTAssertEqual(rows.map(\.text), ["newest", "middle", "oldest"])
    }
}
