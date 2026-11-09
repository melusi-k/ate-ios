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

    /// This is the only candidate route that can build ordinary AppStore/Root graph.
    /// Factory must pass the same lease to EVERY writer and retain the gate. This API
    /// does not supply a factory using today's ungated production constructors.
    func startup<Graph>(authorizeLocalState: @escaping (UUID, AccountResetComposition) throws -> Void,
                        buildGraph: @escaping (UUID, AccountResetComposition) throws -> Graph) -> ResetAwareStartup<Graph> {
        ResetAwareStartup(resume: { [self] in await reset.resumeIfPending() },
            captureAdmission: { [self] in try gate.captureWriter() },
            validateAdmission: { [self] in try gate.validateWriter($0) },
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
