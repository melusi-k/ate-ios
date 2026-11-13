import Foundation

/// Dormant retained proof between async remote reconciliation and ordinary owner
/// construction. No signed-in offline fallback, implicit erase or production RPC.
@MainActor
final class FoodJournalProductionAdmission {
    private struct Proof {
        let lease: UUID
        let session: AuthSession?
        let receipt: AccountGenerationPolicy.Receipt
        let recoveryOwner: String
    }
    private let gate: AccountWriterGate
    private let control: FileResetControlPersistence
    private let receipts: AccountGenerationReceiptStore
    private let resources: FoodJournalDiskResources
    private let archive: ArchiveNestedLeaseBoundary
    private let localIdentity: String
    private let currentSession: () -> AuthSession?
    private let snapshot: (AuthSession) async throws -> AccountSnapshot
    private var proof: Proof?
    private var graphBuilt = false

    init(gate: AccountWriterGate, control: FileResetControlPersistence,
         receipts: AccountGenerationReceiptStore, resources: FoodJournalDiskResources,
         archive: ArchiveNestedLeaseBoundary, localIdentity: String,
         currentSession: @escaping () -> AuthSession?,
         snapshot: @escaping (AuthSession) async throws -> AccountSnapshot) throws {
        guard !localIdentity.isEmpty, control.directory == receipts.directory,
              gate.usesControlDirectory(control.directory) else {
            throw JournalStartupAuthorizationError.blocked("startup control identity mismatch")
        }
        self.gate = gate; self.control = control; self.receipts = receipts
        self.resources = resources; self.archive = archive; self.localIdentity = localIdentity
        self.currentSession = currentSession; self.snapshot = snapshot
    }

    /// Pure preflight: determines who may recover prior archive records, never stamps
    /// adoption. Local-owner to account adoption happens only AFTER that recovery.
    static func recoveryOwner(session: AuthSession?, receipt: AccountGenerationPolicy.Receipt?,
                              remoteGeneration: Int64?, localIdentity: String) throws -> String {
        guard !localIdentity.isEmpty else { throw JournalStartupAuthorizationError.blocked("no stable local identity") }
        if let receipt, receipt.ownerID.isEmpty || receipt.generation < 0 {
            throw JournalStartupAuthorizationError.blocked("invalid local receipt")
        }
        guard let session else { return receipt?.ownerID ?? localIdentity }
        guard !session.userID.isEmpty, let remoteGeneration, remoteGeneration >= 0 else {
            throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
        }
        guard let receipt else {
            guard remoteGeneration == 0 else { throw JournalStartupAuthorizationError.blocked("remote reset requires confirmed local erase") }
            return session.userID
        }
        guard receipt.ownerID == session.userID || receipt.ownerID == localIdentity,
              remoteGeneration == receipt.generation else {
            throw JournalStartupAuthorizationError.blocked("account owner or generation requires reconciliation")
        }
        return receipt.ownerID
    }

    func reconcile(admittedLease: UUID) async throws {
        guard !graphBuilt else { throw JournalStartupAuthorizationError.blocked("retained graph already built") }
        proof = nil
        let session = currentSession()
        let receipt = try gate.withWriterEffect(admittedLease) {
            guard try control.read() == nil else { throw JournalStartupAuthorizationError.blocked("reset still pending") }
            return try receipts.read()
        }
        // No OS lock across network await. A missing/failed snapshot throws before
        // personal store open, recovery, legacy-byte preservation or receipt stamping.
        let remote: AccountSnapshot?
        if let session { remote = try await snapshot(session) } else { remote = nil }
        let owner = try Self.recoveryOwner(session: session, receipt: receipt,
            remoteGeneration: remote?.generation, localIdentity: localIdentity)
        func verifyOriginal() throws {
            guard currentSession() == session, try control.read() == nil,
                  try receipts.read() == receipt else { throw JournalStartupAuthorizationError.blocked("startup identity changed") }
        }
        try resources.recover(gate: gate, admittedLease: admittedLease, ownerIdentity: owner,
            authorizeRecovery: verifyOriginal)
        let perform = JournalWriterBoundaryComposition.makePerform(gate: gate,
            writerLease: admittedLease, archive: archive)
        let reconciliation = JournalInstallReconciliation(receiptStore: receipts, control: control,
            preservationDirectory: resources.locations.preservationDirectory,
            legacyDiary: NutritionDiaryRepository(defaults: resources.defaults,
                backupDirectory: resources.locations.repairBackupDirectory),
            goals: NutritionGoalsRepository(defaults: resources.defaults, storage: resources.goalsStorage),
            snapshot: { candidate in
                guard candidate == session, let remote else { throw JournalStartupAuthorizationError.blocked("startup session changed") }
                return remote
            }, currentSession: currentSession, localIdentity: localIdentity,
            stampEffect: { work in
                try perform {
                    try verifyOriginal()
                    try work()
                }
            })
        _ = try await reconciliation.reconcile()
        let expectedReceipt = AccountGenerationPolicy.Receipt(
            ownerID: session?.userID ?? receipt?.ownerID ?? localIdentity,
            generation: remote?.generation ?? receipt?.generation ?? 0)
        try gate.withWriterEffect(admittedLease) {
            guard currentSession() == session, try control.read() == nil,
                  let finalReceipt = try receipts.read(), finalReceipt == expectedReceipt else { throw JournalStartupAuthorizationError.blocked("startup proof missing") }
            proof = Proof(lease: admittedLease, session: session, receipt: finalReceipt, recoveryOwner: owner)
        }
    }

    func validate(admittedLease: UUID) throws {
        try gate.withWriterEffect(admittedLease) {
            guard let proof, proof.lease == admittedLease, currentSession() == proof.session,
                  try control.read() == nil, try receipts.read() == proof.receipt else {
                throw JournalStartupAuthorizationError.blocked("startup proof changed")
            }
        }
    }
    /// Build one dormant retained graph from this exact reconciled proof. None of
    /// its resources or callbacks are installed in the application root here.
    func buildGraph(admittedLease: UUID, afterRestoreCommit: @escaping () throws -> Void) throws -> FoodJournalProductionGraph {
        guard !graphBuilt else { throw JournalStartupAuthorizationError.blocked("retained graph already built") }
        try validate(admittedLease: admittedLease)
        guard let captured = proof else { throw JournalStartupAuthorizationError.blocked("startup proof missing") }
        let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: admittedLease,
            session: captured.session, currentSession: currentSession)
        let owner = try bindOwner(admittedLease: admittedLease, afterRestoreCommit: afterRestoreCommit,
            validateConsumers: lifecycle.validate)
        let recipes = try resources.recipeContainer(gate: gate, admittedLease: admittedLease)
        // This proof remains valid for the closed graph's ONE archive operation.
        // Its caller holds the replacement epoch under the same gate, so do not
        // check the deliberately revoked ordinary writer lease here.
        let retainedIdentity: () throws -> Void = {
            guard self.proof?.lease == captured.lease,
                  self.currentSession() == captured.session,
                  try self.control.read() == nil,
                  try self.receipts.read() == captured.receipt else {
                throw JournalStartupAuthorizationError.blocked("retained owner identity changed")
            }
        }
        let export = FoodJournalArchiveExport(owner: owner, recipes: recipes, gate: gate,
            admittedLease: admittedLease, validateOwner: {
                try self.validate(admittedLease: admittedLease)
                try lifecycle.validate()
            })
        let importer = try FoodJournalArchiveImport(owner: owner, recipes: recipes, lifecycle: lifecycle,
            ownerIdentity: captured.receipt.ownerID, authorizeOperation: retainedIdentity)
        graphBuilt = true
        return FoodJournalProductionGraph(owner: owner, lifecycle: lifecycle, export: export, importer: importer)
    }

    func bindOwner(admittedLease: UUID, afterRestoreCommit: @escaping () throws -> Void,
                   validateConsumers: @escaping () throws -> Void = {}) throws -> FoodJournalLocalOwner {
        try validate(admittedLease: admittedLease)
        guard let proof else { throw JournalStartupAuthorizationError.blocked("startup proof missing") }
        return try resources.bindOwner(gate: gate, admittedLease: admittedLease, ownerIdentity: proof.recoveryOwner,
            archive: archive, authorizeBinding: { try self.validate(admittedLease: admittedLease) },
            afterRestoreCommit: afterRestoreCommit, validateConsumers: validateConsumers)
    }
}


/// Dormant graph value returned only by reconciled admission. Root integration
/// still owns real consumer registration, visible-editor dismissal, async drain,
/// auth transitions, post-import rebuild and UI publication. Activation stays OFF.
@MainActor
final class FoodJournalProductionGraph {
    let owner: FoodJournalLocalOwner
    let lifecycle: FoodJournalConsumerLifecycle
    let archiveExport: FoodJournalArchiveExport
    let archiveImport: FoodJournalArchiveImport

    // Only admission in this source file constructs this value. Consumers use
    // ProductionAdmission.buildGraph, never individually assemble storage roots.
    fileprivate init(owner: FoodJournalLocalOwner, lifecycle: FoodJournalConsumerLifecycle,
         export: FoodJournalArchiveExport, importer: FoodJournalArchiveImport) {
        self.owner = owner; self.lifecycle = lifecycle
        self.archiveExport = export; self.archiveImport = importer
    }
    var runtime: FoodJournalRuntime { owner.runtime }
    var resetInventory: JournalLocalReset { owner.resetInventory }
    func validate() throws {
        try owner.requireLifecycle(lifecycle)
    }
    func quiesce() async throws { try await lifecycle.quiesce() }
}
