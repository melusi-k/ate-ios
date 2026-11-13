import Foundation

/// Retains the proof between async reconciliation and ordinary graph construction.
/// Device-local (signed-out) admission never requires a server snapshot. An existing
/// signed-in session ALWAYS requires the snapshot contract; there is no implicit
/// fallback to device-local ownership when the contract is absent or unverifiable.
@MainActor
final class FoodJournalProductionAdmission {
    private struct Proof {
        let lease: UUID
        let session: AuthSession?
        let receipt: AccountGenerationPolicy.Receipt
    }

    let composition: AccountResetComposition
    private let archive: ArchiveNestedLeaseBoundary
    private let preservationDirectory: URL
    private let legacyDiary: NutritionDiaryRepository
    private let goals: NutritionGoalsRepository
    private let snapshot: (AuthSession) async throws -> AccountSnapshot
    private let currentSession: () -> AuthSession?
    private let localIdentity: String
    private let recoverArchive: (String) throws -> Void
    private var proof: Proof?

    init(composition: AccountResetComposition, archive: ArchiveNestedLeaseBoundary,
         preservationDirectory: URL, legacyDiary: NutritionDiaryRepository,
         goals: NutritionGoalsRepository,
         snapshot: @escaping (AuthSession) async throws -> AccountSnapshot,
         currentSession: @escaping () -> AuthSession?, localIdentity: String,
         recoverArchive: @escaping (String) throws -> Void) {
        self.composition = composition
        self.archive = archive
        self.preservationDirectory = preservationDirectory
        self.legacyDiary = legacyDiary
        self.goals = goals
        self.snapshot = snapshot
        self.currentSession = currentSession
        self.localIdentity = localIdentity
        self.recoverArchive = recoverArchive
    }

    func reconcile(lease: UUID) async throws {
        proof = nil
        guard !localIdentity.isEmpty else {
            throw JournalStartupAuthorizationError.blocked("no stable local identity supplied")
        }
        let session = currentSession()
        let receipt = try composition.gate.withWriterEffect(lease) {
            try composition.receipt.read()
        }
        // Establish the account generation without any preservation/adoption write.
        // Raw archive recovery must precede the ordinary archive boundary: that
        // boundary intentionally refuses an unresolved transaction.
        let verifiedSnapshot: AccountSnapshot?
        if let session {
            do { verifiedSnapshot = try await snapshot(session) }
            catch { throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable") }
        } else { verifiedSnapshot = nil }
        try composition.gate.withWriterEffect(lease) {
            guard currentSession() == session, try composition.receipt.read() == receipt else {
                throw JournalStartupAuthorizationError.blocked("startup identity or generation changed")
            }
            let owner = try authorizedRecoveryOwner(session: session, receipt: receipt,
                remoteGeneration: verifiedSnapshot?.generation)
            try recoverArchive(owner)
        }
        let perform = JournalWriterBoundaryComposition.makePerform(
            gate: composition.gate, writerLease: lease, archive: archive)
        let reconciliation = JournalInstallReconciliation(receiptStore: composition.receipt,
            control: composition.control, preservationDirectory: preservationDirectory,
            legacyDiary: legacyDiary, goals: goals, snapshot: { candidate in
                guard candidate == session, let verifiedSnapshot else {
                    throw JournalStartupAuthorizationError.blocked("sign-in changed during startup")
                }
                return verifiedSnapshot
            },
            currentSession: currentSession, localIdentity: localIdentity, stampEffect: perform)
        _ = try await reconciliation.reconcile()
        // The same account can sign out/in during the await. Comparing only userID
        // would accept old work under a new session. Preserve the full session proof.
        try composition.gate.withWriterEffect(lease) {
            guard currentSession() == session else {
                throw JournalStartupAuthorizationError.blocked("sign-in changed during startup")
            }
            guard let receipt = try composition.receipt.read() else {
                throw JournalStartupAuthorizationError.blocked("generation receipt missing after reconciliation")
            }
            proof = Proof(lease: lease, session: session, receipt: receipt)
        }
    }

    /// Pure preflight mirrors reconciliation's ownership/generation table without
    /// stamping a receipt. A foreign or reset account cannot authorize raw recovery.
    private func authorizedRecoveryOwner(session: AuthSession?,
                                         receipt: AccountGenerationPolicy.Receipt?,
                                         remoteGeneration: Int64?) throws -> String {
        guard let session else { return receipt?.ownerID ?? localIdentity }
        guard !session.userID.isEmpty, let remoteGeneration, remoteGeneration >= 0 else {
            throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable")
        }
        guard let receipt else {
            guard remoteGeneration == 0 else {
                throw JournalStartupAuthorizationError.blocked("remote reset committed; confirmed local erase required")
            }
            return session.userID
        }
        guard receipt.ownerID == session.userID || receipt.ownerID == localIdentity else {
            throw JournalStartupAuthorizationError.blocked("local records belong to a different account")
        }
        guard remoteGeneration == receipt.generation else {
            throw JournalStartupAuthorizationError.blocked(remoteGeneration > receipt.generation
                ? "remote reset committed; confirmed local erase required" : "remote generation regressed")
        }
        // Existing recovery records belong to the receipt's owner. Adoption into
        // a signed-in account happens only AFTER its local recovery is complete.
        return receipt.ownerID
    }

    /// Synchronous, read-only proof under the original account gate. No snapshot await
    /// or empty archive effect here: validation must not stamp another generation.
    func validate(lease: UUID, composition candidate: AccountResetComposition) throws {
        guard candidate === composition, let proof, proof.lease == lease else {
            throw JournalStartupAuthorizationError.blocked("startup admission proof missing")
        }
        try composition.gate.withWriterEffect(lease) {
            guard try composition.control.read() == nil,
                  currentSession() == proof.session,
                  try composition.receipt.read() == proof.receipt else {
                throw JournalStartupAuthorizationError.blocked("startup identity or generation changed")
            }
        }
    }

    func startup(backend: BackendService,
                 makeResources: @escaping (FoodJournalWriterBoundary) throws -> FoodJournalAppGraph.Resources,
                 makeConsumers: @escaping (FoodJournalRuntime) throws -> FoodJournalConsumerBindings
    ) -> ResetAwareStartup<FoodJournalAppGraph> {
        FoodJournalAppGraph.startup(composition: composition, archive: archive, backend: backend,
            authorizeLocalState: { [self] lease, composition in try validate(lease: lease, composition: composition) },
            authorizeAdmission: { [self] lease in try await reconcile(lease: lease) },
            makeResources: makeResources, makeConsumers: makeConsumers)
    }
}
