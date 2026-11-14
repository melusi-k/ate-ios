import Foundation

/// The ordinary AppStore sync loop still owns merge/UI reporting. This adapter
/// replaces only its transport: no legacy table POST, fresh-generation adoption,
/// or silently stamped owner switch. One pull capture authorizes its exact push.
@MainActor
final class FoodJournalGenerationSync: SyncService {
    enum Failure: Error { case missingPull, identityChanged, reconciliationRequired, operationInProgress, localRevisionChanged }
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
    /// One retained transport owner excludes ordinary pull/push and family cycles
    /// for the complete snapshot/upload/commit interval. The commit is synchronous
    /// and MUST bind the graph's durable journal and actual ordinary writer effect.
    /// This seam is not installed by the production host until journal routing,
    /// startup replay and reset inventory are complete.
    struct LocalSnapshot: Equatable {
        let recipes: [RecipeCard]
        let shopping: [ShoppingItem]
        let metadata: RecipeShoppingSyncStage.Metadata
    }
    func syncRecipeShopping(session: AuthSession,
                            readLocal: () throws -> LocalSnapshot,
                            commit: (RecipeShoppingSyncStage, LocalSnapshot, AccountGenerationPolicy.Receipt) throws -> Void) async throws -> Int {
        guard !busy, pending == nil else { throw Failure.operationInProgress }
        busy = true
        defer { busy = false; pending = nil }
        try Task.checkCancellation()
        try validate()
        guard currentSession() == session else { throw Failure.identityChanged }
        let local = try readLocal()
        let snapshot = try await fenced.snapshot()
        try Task.checkCancellation()
        try require(session, capture: snapshot.capture)
        guard try readLocal() == local else { throw Failure.localRevisionChanged }
        // Other independently owned families are not recipe/shopping input. No
        // unsupported family is decoded, dropped from the server or uploaded here.
        let rows = snapshot.rows.filter { $0.kind == "recipe" || $0.kind == "shopping" }
        let stage = try RecipeShoppingSyncStage.prepare(recipes: local.recipes,
            shopping: local.shopping, metadata: local.metadata, remote: rows, ownerID: session.userID)
        try await fenced.push(stage.upload, capture: snapshot.capture)
        try Task.checkCancellation()
        try require(session, capture: snapshot.capture)
        guard try readLocal() == local else { throw Failure.localRevisionChanged }
        // No await after final comparison. Commit must re-prove the same expected
        // local image under its held writer boundary and publish memory only AFTER
        // journal durability. A partial upload never consumes local pending state.
        try commit(stage, local, .init(ownerID: snapshot.capture.ownerID, generation: snapshot.capture.generation))
        return stage.upload.count
    }

}
