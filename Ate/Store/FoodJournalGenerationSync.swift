import Foundation

/// The ordinary AppStore sync loop still owns merge/UI reporting. This adapter
/// replaces only its transport: no legacy table POST, fresh-generation adoption,
/// or silently stamped owner switch. One pull capture authorizes its exact push.
@MainActor
final class FoodJournalGenerationSync: SyncService {
    enum Failure: Error { case missingPull, identityChanged, reconciliationRequired, operationInProgress }
    private let fenced: GenerationFencedSync
    private let receipts: AccountGenerationReceiptStore
    private let validate: () throws -> Void
    private let currentSession: () -> AuthSession?
    private var busy = false
    private var pending: GenerationFencedSync.Capture?

    init(fenced: GenerationFencedSync, receipts: AccountGenerationReceiptStore,
         currentSession: @escaping () -> AuthSession?, validate: @escaping () throws -> Void) {
        self.fenced = fenced; self.receipts = receipts
        self.currentSession = currentSession; self.validate = validate
    }

    private func require(_ session: AuthSession, capture: GenerationFencedSync.Capture) throws {
        try validate()
        guard currentSession() == session, capture.ownerID == session.userID else { throw Failure.identityChanged }
        guard let receipt = try receipts.read(),
              receipt.ownerID == capture.ownerID, receipt.generation == capture.generation else {
            throw Failure.reconciliationRequired
        }
    }

    func pull(session: AuthSession) async throws -> [SyncRecord] {
        guard !busy else { throw Failure.operationInProgress }
        busy = true
        defer { busy = false }
        pending = nil
        try validate()
        guard currentSession() == session else { throw Failure.identityChanged }
        let snapshot = try await fenced.snapshot()
        try Task.checkCancellation()
        try require(session, capture: snapshot.capture)
        pending = snapshot.capture
        return snapshot.rows
    }

    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        guard !busy else { throw Failure.operationInProgress }
        busy = true
        defer { busy = false }
        guard let capture = pending else { throw Failure.missingPull }
        // Single use even on failure. Next attempt must snapshot/reconcile again.
        pending = nil
        try require(session, capture: capture)
        try await fenced.push(records, capture: capture)
        try Task.checkCancellation()
        try require(session, capture: capture)
    }
}
