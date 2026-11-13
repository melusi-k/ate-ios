import XCTest
import SwiftData
@testable import Ate

/// Native UNRUN. Isolated defaults, real admission gate, no production route.
@MainActor
final class RecipeShoppingLocalServicesTests: XCTestCase {
    func testRefusingServicesCannotResetDraftHistoryOrTimerBytesBeforeAdmission() throws {
        let suite = "LocalServices-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let history = Data(#"{"2026-11-13":["existing"]}"#.utf8)
        let draft = Data("preserved-corrupt-draft".utf8), timers = Data("preserved-corrupt-timers".utf8)
        d.set(history, forKey: "ate.cooking.history.v1"); d.set(draft, forKey: "ate.draft.card.v1"); d.set(timers, forKey: TimerSnapshot.key)
        let services = RecipeShoppingLocalServices.refusing(defaults: d)
        XCTAssertFalse(services.drafts.clear()); XCTAssertFalse(services.drafts.begin(mode: "text", text: "blocked"))
        services.history.clear(); services.history.record(recipeID: "blocked")
        XCTAssertEqual(services.timers.kitchenToggle(), "unavailable")
        XCTAssertEqual(d.data(forKey: "ate.cooking.history.v1"), history)
        XCTAssertEqual(d.data(forKey: "ate.draft.card.v1"), draft)
        XCTAssertEqual(d.data(forKey: TimerSnapshot.key), timers)
        XCTAssertNil(services.journal.container)
    }
    func testAdmittedLocalServicesUseExactDefaultsAndOldServicesRefuseAfterEpochRetirement() async throws {
        let suite = "AdmittedServices-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL; defer { try? FileManager.default.removeItem(at: root) }
        let commit = root.appendingPathComponent(RecipeShoppingSyncCommitJournal.directoryName)
        try FileManager.default.createDirectory(at: commit, withIntermediateDirectories: false)
        let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000, userID: "owner", email: "fixture@example.test")
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false }); let lease = try gate.captureWriter()
        try gate.withWriterEffect(lease) { try AccountGenerationReceiptStore(directory: root).save(.init(ownerID: "owner", generation: 0)) }
        let rpc = AccountDataResetService(baseURL: URL(string: "https://fixture.invalid")!, key: "fixture", perform: { request in
            (Data(#"{"generation":0,"rows":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let owner = try RecipeShoppingSyncOwner(controlDirectory: root, rpc: rpc, session: session, currentSession: { session })
        _ = try await owner.pull(session: session); try await owner.push([], session: session)
        var metadata = RecipeShoppingSyncStage.Metadata(); metadata.userID = "owner"
        d.set(try JSONEncoder().encode(metadata), forKey: "ate.sync.v1")
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let resources = try RecipeShoppingAdmittedResources.open(owner: owner, session: session, defaults: d, commitDirectory: commit,
            validateWriterRouting: {}, makeContainer: { container })
        let services = try RecipeShoppingLocalServices.admitted(resources: resources, sharedDefaults: d) { boundary in
            let journal = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return JournalStore(container: journal, openState: .ok, writerBoundary: boundary)
        }
        XCTAssertTrue(services.validates(resources.binding))
        XCTAssertTrue(services.drafts.begin(mode: "text", text: "kept"))
        services.history.record(recipeID: "cooked")
        let before = d.dictionaryRepresentation()
        try owner.retireForSessionTransition()
        XCTAssertFalse(services.validates(resources.binding)); XCTAssertFalse(services.drafts.clear())
        services.history.clear()
        XCTAssertEqual(d.data(forKey: "ate.draft.pending.v1"), before["ate.draft.pending.v1"] as? Data)
        XCTAssertEqual(d.data(forKey: "ate.cooking.history.v1"), before["ate.cooking.history.v1"] as? Data)
        let remounted = try RecipeShoppingSyncOwner(controlDirectory: root, rpc: rpc, session: session, currentSession: { session })
        _ = try await remounted.pull(session: session); try await remounted.push([], session: session)
        let next = try RecipeShoppingAdmittedResources.open(owner: remounted, session: session, defaults: d, commitDirectory: commit,
            validateWriterRouting: {}, makeContainer: { container })
        enum Injected: Error { case unavailableJournal }
        let captured = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
        XCTAssertThrowsError(try RecipeShoppingLocalServices.admitted(resources: next, sharedDefaults: d) { _ in
            throw Injected.unavailableJournal
        })
        XCTAssertThrowsError(try captured.withEffect { XCTFail("failed graph left extension writable") })
        let afterFailure = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
        XCTAssertThrowsError(try afterFailure.withEffect { XCTFail("failed graph reused readiness") })
    }
}
