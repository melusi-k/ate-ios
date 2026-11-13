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
    func bindOwner(admittedLease: UUID, afterRestoreCommit: @escaping () throws -> Void) throws -> FoodJournalLocalOwner {
        try validate(admittedLease: admittedLease)
        guard let proof else { throw JournalStartupAuthorizationError.blocked("startup proof missing") }
        return try resources.bindOwner(gate: gate, admittedLease: admittedLease, ownerIdentity: proof.recoveryOwner,
            archive: archive, authorizeBinding: { try self.validate(admittedLease: admittedLease) },
            afterRestoreCommit: afterRestoreCommit)
    }
}
