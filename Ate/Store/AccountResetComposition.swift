import Foundation

extension AppStore {
    /// Candidate states only. Settings ordinary action is NOT rebound by this source.
    enum ClearAllState: Equatable {
        case unavailable(String)
        case serverOutcomeUnverified
        case cloudCommittedLocalIncomplete([String])
        case completed
    }
}

/// Actual candidate dependency graph, no default construction in AteApp. Participants
/// and the shared directory are REQUIRED injected values; there is no fabricated empty
/// component/surface implementation. Assemble only before ordinary constructors.
@MainActor
final class AccountResetComposition {
    let control: FileResetControlPersistence
    let receipt: AccountGenerationReceiptStore
    let gate: AccountWriterGate
    let reset: ClearAllResetCoordinator
    let sync: GenerationFencedSync

    init(controlDirectory: URL, rpc: AccountDataResetService,
         currentSession: @escaping () -> AuthSession?,
         surfaces: ClearAllSystemSurfaceCleaning,
         components: @escaping () throws -> ([ClearAllLocalData.Component], Set<String>)) throws {
        let control = FileResetControlPersistence(directory: controlDirectory)
        _ = try control.read() // missing/untrusted parent is NOT an absent reset
        let receipt = try AccountGenerationReceiptStore(directory: controlDirectory)
        let gate = try AccountWriterGate(directory: controlDirectory,
            resetControlExists: { try control.read() != nil })
        self.control = control
        self.receipt = receipt
        self.gate = gate
        reset = ClearAllResetCoordinator(rpc: rpc, gate: gate, surfaces: surfaces,
            controlPersistence: control, currentSession: currentSession,
            receiptSink: { generation in
                try gate.validateResetGate()
                guard let owner = currentSession()?.userID, !owner.isEmpty else {
                    throw ResetRPCError.unauthorized
                }
                try receipt.save(.init(ownerID: owner, generation: generation))
                try gate.validateResetGate()
            }, components: components)
        sync = GenerationFencedSync(rpc: rpc, currentSession: currentSession,
            captureWriter: { try gate.captureWriter() },
            validateWriter: { try gate.validateWriter($0) })
    }

    func admittedSyncService(lease: UUID) -> GenerationFencedSyncService {
        GenerationFencedSyncService(adapter: sync, receipt: { [self] in
            try gate.withWriterEffect(lease) { try receipt.read() }
        }, invalidateWriters: { [self] in try gate.blockWritersForGenerationConflict() })
    }

    /// This is the only candidate route that can build ordinary AppStore/Root graph.
    /// Factory must pass the same lease to EVERY writer and retain the gate. This API
    /// does not supply a factory using today's ungated production constructors.
    /// authorizeLocalState stays synchronous and runs INSIDE gate.withWriterEffect:
    /// strict receipt/control validation only, never an await under the flock.
    /// authorizeAdmission is the async admission phase (central's ResetAwareStartup runs
    /// it after captureAdmission, before final validation/buildGraph): unfenced awaits
    /// such as JournalInstallReconciliation's snapshot RPC belong there, with their
    /// final durable writes re-validated and stamped in a short gate effect.
    func startup<Graph>(authorizeLocalState: @escaping (UUID, AccountResetComposition) throws -> Void,
                        authorizeAdmission: @escaping (UUID) async throws -> Void = { _ in },
                        buildGraph: @escaping (UUID, AccountResetComposition) throws -> Graph) -> ResetAwareStartup<Graph> {
        ResetAwareStartup(resume: { [self] in await reset.resumeIfPending() },
            captureAdmission: { [self] in try gate.captureWriter() },
            validateAdmission: { [self] in try gate.validateWriter($0) },
            authorizeAdmission: authorizeAdmission,
            buildGraph: { [self] lease in
                try gate.withWriterEffect(lease) {
                    // Must evaluate strict persisted receipt + verified remote epoch policy
                    // BEFORE ordinary constructors may load, migrate or write personal data.
                    try authorizeLocalState(lease, self)
                    return try buildGraph(lease, self)
                }
            })
    }
}

/// Activation gate for generation-aware sync, not migration qualification.
/// Deliberately has no retry or Refresh callback until recovery/quiescence is real.
enum AccountGenerationConflictState: Equatable {
    case staleLocalData
    case pendingResetUnverified

    enum Operation { case snapshot, put, clear }
    static func failure(_ error: ResetRPCError, during operation: Operation,
                        hasPendingReset: Bool) -> Self? {
        guard error == .staleGeneration else { return nil }
        if hasPendingReset { return .pendingResetUnverified }
        switch operation {
        case .clear: return .pendingResetUnverified
        case .snapshot, .put: return .staleLocalData
        }
    }
    var title: String {
        switch self {
        case .staleLocalData: return "Your account data changed"
        case .pendingResetUnverified: return "Your account-data request needs checking"
        }
    }
    var message: String {
        switch self {
        case .staleLocalData:
            return "This iPhone has an older version of your account data. Sync is paused so it doesn't upload old data again. Ate needs to check the current account before you can continue."
        case .pendingResetUnverified:
            return "Ate couldn't confirm this request because your account data changed. Saved data is staying closed. Checking status won't start another Clear all request."
        }
    }
    var recoveryStatus: String {
        "Account status checking is not available in this build. Saved data must stay closed until safe recovery is available."
    }
}
