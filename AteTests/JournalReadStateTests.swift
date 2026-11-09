import XCTest
import SwiftData
@testable import Ate

/// Shared journal read state: a failed read is an explicit error on every Journal surface,
/// never an empty journal, and filter/search stay disabled until a read succeeds.
@MainActor
final class JournalReadStateTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func entry(text: String, createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Ate.JournalEntry {
        Ate.JournalEntry(createdAt: createdAt, prompt: "", text: text, state: nil)
    }

    func testReadEntriesThrowsWhenTheStoreIsUnavailable() {
        let store = JournalStore(container: nil, openState: .unavailable(error: "test"))
        XCTAssertThrowsError(try store.readEntries()) { error in
            XCTAssertEqual(error as? JournalReadError, .storeUnavailable)
        }
        XCTAssertEqual(store.entries(), [], "the intent-facing read still answers without throwing")
    }

    func testReadEntriesReturnsEntriesNewestFirst() throws {
        let container = try makeContainer()
        let store = JournalStore(container: container, openState: .ok)
        let context = try XCTUnwrap(store.container?.mainContext)
        context.insert(entry(text: "older", createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
        context.insert(entry(text: "newer", createdAt: Date(timeIntervalSince1970: 1_800_000_000)))
        try context.save()
        XCTAssertEqual(try store.readEntries().map(\.text), ["newer", "older"])
    }

    func testReadEntryThrowsForUnavailableStoreAndDistinguishesMissingFromFailed() throws {
        let unavailable = JournalStore(container: nil, openState: .unavailable(error: "test"))
        XCTAssertThrowsError(try unavailable.readEntry("any")) { error in
            XCTAssertEqual(error as? JournalReadError, .storeUnavailable)
        }
        let container = try makeContainer()
        let store = JournalStore(container: container, openState: .ok)
        let context = try XCTUnwrap(store.container?.mainContext)
        let kept = entry(text: "kept")
        context.insert(kept)
        try context.save()
        XCTAssertEqual(try store.readEntry(kept.id)?.text, "kept")
        XCTAssertNil(try store.readEntry("missing-id"), "nil means genuinely gone, not a read failure")
    }

    // MARK: Root Journal list content decisions

    func testListLoadingIsLoading() {
        XCTAssertEqual(JournalListContent.make(state: .loading, openState: .ok, filteredCount: 0), .loading)
    }

    func testListReadFailureIsAnErrorNotAnEmptyJournal() {
        XCTAssertEqual(JournalListContent.make(state: .failed(.readFailed), openState: .ok, filteredCount: 0),
                       .readError(.readFailed))
        XCTAssertEqual(JournalListContent.make(state: .failed(.storeUnavailable), openState: .ok, filteredCount: 0),
                       .readError(.storeUnavailable))
    }

    func testListEmptyHealthyJournalSaysSo() {
        XCTAssertEqual(JournalListContent.make(state: .loaded([]), openState: .ok, filteredCount: 0), .emptyJournal)
    }

    func testListEmptyWithNonOkOpenStateIsSuppressed() {
        XCTAssertEqual(JournalListContent.make(state: .loaded([]), openState: .recovered(backupName: "b"), filteredCount: 0),
                       .emptySuppressed)
        XCTAssertEqual(JournalListContent.make(state: .loaded([]), openState: .inMemoryFallback(error: nil), filteredCount: 0),
                       .emptySuppressed)
        XCTAssertEqual(JournalListContent.make(state: .loaded([]), openState: .unavailable(error: nil), filteredCount: 0),
                       .emptySuppressed)
    }

    func testListNoFilterHitsIsNoMatchesNotEmptyJournal() {
        let entries = [entry(text: "soup")]
        XCTAssertEqual(JournalListContent.make(state: .loaded(entries), openState: .ok, filteredCount: 0), .noMatches)
        XCTAssertEqual(JournalListContent.make(state: .loaded(entries), openState: .ok, filteredCount: 1), .entries)
    }

    // MARK: Filter/search gating

    func testRootListSearchHiddenUntilAReadSucceeds() {
        XCTAssertFalse(JournalListView.controlsVisible(for: .loading))
        XCTAssertFalse(JournalListView.controlsVisible(for: .failed(.readFailed)))
        XCTAssertFalse(JournalListView.controlsVisible(for: .failed(.storeUnavailable)))
        XCTAssertTrue(JournalListView.controlsVisible(for: .loaded([])))
        XCTAssertTrue(JournalListView.controlsVisible(for: .loaded([entry(text: "soup")])))
    }

    func testTimelineControlsHiddenUntilAReadSucceeds() {
        XCTAssertFalse(JournalTimelineView.controlsVisible(for: .loading))
        XCTAssertFalse(JournalTimelineView.controlsVisible(for: .failed(.readFailed)))
        XCTAssertFalse(JournalTimelineView.controlsVisible(for: .failed(.storeUnavailable)))
        XCTAssertTrue(JournalTimelineView.controlsVisible(for: .loaded([])))
    }
}
