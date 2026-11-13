import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalConsumerLifecycleTests: XCTestCase {
    private enum Injected: Error { case drain }
    private func fixture(_ run: (URL, AccountWriterGate, UUID) async throws -> Void) async throws {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent("ConsumerLifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        try await run(root, gate, gate.captureWriter())
    }
    private func session(_ token: String) -> AuthSession {
        .init(accessToken: token, refreshToken: "fixture", expiresAt: 4_102_444_800,
              userID: "same-account", email: "fixture@example.invalid")
    }
    func testSameAccountSessionMutationRefusesValidationAndNewConsumers() async throws {
        try await fixture { _, gate, lease in
            var current: AuthSession? = self.session("first")
            let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease,
                session: current, currentSession: { current })
            try lifecycle.validate()
            current = self.session("second")
            XCTAssertThrowsError(try lifecycle.validate())
            XCTAssertThrowsError(try lifecycle.register(cancel: {}, drain: {}))
            current = nil
            XCTAssertThrowsError(try lifecycle.validate())
        }
    }
    func testQuiescenceRevokesBeforeCancellationAndAwaitsEveryDrain() async throws {
        try await fixture { _, gate, lease in
            let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease,
                session: nil, currentSession: { nil })
            var cancelled = 0, drained = 0
            for _ in 0..<2 {
                try lifecycle.register(cancel: {
                    XCTAssertEqual(lifecycle.state, .quiescing)
                    XCTAssertThrowsError(try gate.validateWriter(lease))
                    XCTAssertThrowsError(try lifecycle.register(cancel: {}, drain: {}))
                    cancelled += 1
                }, drain: {
                    await Task.yield()
                    XCTAssertEqual(cancelled, 2)
                    XCTAssertEqual(lifecycle.state, .quiescing)
                    drained += 1
                })
            }
            try await lifecycle.quiesce()
            XCTAssertEqual(cancelled, 2); XCTAssertEqual(drained, 2)
            XCTAssertEqual(lifecycle.state, .quiesced)
            XCTAssertThrowsError(try lifecycle.validate())
            try await lifecycle.quiesce()
            XCTAssertEqual(cancelled, 2, "Successful quiescence is idempotent")
        }
    }
    func testFailedDrainStillDrainsOtherConsumersAndCannotPublishCompletion() async throws {
        try await fixture { _, gate, lease in
            let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease,
                session: nil, currentSession: { nil })
            var drained = 0
            try lifecycle.register(cancel: {}, drain: { drained += 1; throw Injected.drain })
            try lifecycle.register(cancel: {}, drain: { drained += 1 })
            do { try await lifecycle.quiesce(); XCTFail("Failed drain must refuse completion") } catch { }
            XCTAssertEqual(drained, 2)
            XCTAssertEqual(lifecycle.state, .quiescing)
            XCTAssertThrowsError(try lifecycle.validate())
        }
    }
    func testStaleGraphQuiescenceCannotInvalidateReplacementEpoch() async throws {
        try await fixture { _, gate, lease in
            let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease,
                session: nil, currentSession: { nil })
            try gate.invalidateWriters(expectedLease: lease)
            let replacement = try gate.captureWriter()
            var cancelled = false
            // Registering after invalidation is refused, so this stale graph has no new tasks.
            XCTAssertThrowsError(try lifecycle.register(cancel: { cancelled = true }, drain: {}))
            do { try await lifecycle.quiesce(); XCTFail("Old graph must not revoke new epoch") } catch { }
            try gate.validateWriter(replacement)
            XCTAssertFalse(cancelled)
            XCTAssertEqual(lifecycle.state, .quiescing)
        }
    }
    func testBoundOwnerRefusesRealReflectionEffectAfterSameOwnerSessionChange() async throws {
        try await fixture { root, gate, lease in
            let suite = "LifecycleBoundOwner-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var current: AuthSession? = self.session("first")
            let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: lease,
                session: current, currentSession: { current })
            let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
            let owner = try FoodJournalLocalOwner.bind(container: container, openState: .ok, defaults: defaults,
                goalsStorage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")),
                locations: .init(storeFileURL: root.appendingPathComponent("journal.store"),
                    mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
                    repairBackupDirectory: root.appendingPathComponent("repair"), preservationDirectory: root.appendingPathComponent("preservation")),
                gate: gate, admittedLease: lease, archive: ArchiveNestedGenerationBoundary(directory: root),
                afterRestoreCommit: {}, validateConsumers: lifecycle.validate)
            _ = try owner.runtime.journal.saveManual(text: "Before auth change")
            current = self.session("second")
            XCTAssertThrowsError(try owner.runtime.journal.saveManual(text: "Must not save"))
            XCTAssertThrowsError(try owner.validate())
            XCTAssertEqual(try owner.runtime.journal.readReflections().map(\.text), ["Before auth change"])
        }
    }
}
