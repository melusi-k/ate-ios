import Foundation

/// Dormant retained lifecycle for one admitted graph. Root composition must register
/// every asynchronous consumer and bind validate() into that owner's write boundary.
/// A new graph is never published until quiesce() succeeds; no lease is recaptured here.
@MainActor
final class FoodJournalConsumerLifecycle {
    enum State { case active, quiescing, quiesced }
    enum Failure: Error { case inactive, sessionChanged }
    private(set) var state: State = .active
    private let gate: AccountWriterGate
    private let admittedLease: UUID
    private let session: AuthSession?
    private let currentSession: () -> AuthSession?
    private struct Consumer {
        let cancel: () -> Void
        let drain: () async throws -> Void
    }
    private var consumers: [UUID: Consumer] = [:]
    private var quiescedOperationLease: UUID?
    private var operationConsumed = false

    init(gate: AccountWriterGate, admittedLease: UUID, session: AuthSession?,
         currentSession: @escaping () -> AuthSession?) {
        self.gate = gate; self.admittedLease = admittedLease
        self.session = session; self.currentSession = currentSession
    }

    func belongs(to candidate: AccountWriterGate, lease: UUID) -> Bool {
        gate === candidate && admittedLease == lease
    }

    func validate() throws {
        guard state == .active else { throw Failure.inactive }
        guard currentSession() == session else { throw Failure.sessionChanged }
        try gate.validateWriter(admittedLease)
    }

    /// Registration precedes starting a consumer. Cancellation alone is not proof
    /// that it stopped: drain must await its actual completion, not schedule it.
    @discardableResult
    func register(cancel: @escaping () -> Void,
                  drain: @escaping () async throws -> Void) throws -> UUID {
        try validate()
        let id = UUID()
        consumers[id] = Consumer(cancel: cancel, drain: drain)
        return id
    }

    /// Completion is cleanup, not new admission. A quiescence snapshot retains
    /// its drain closure even when the task removes itself while being awaited.
    func finishedConsumer(_ id: UUID) { consumers.removeValue(forKey: id) }

    /// One operation on the closed graph, under the replacement epoch produced by
    /// revoking THIS graph. Never capture a lease or expose it to ordinary consumers.
    /// The supplied full owner/receipt proof executes under the held account flock.
    func withQuiescedArchiveOperation<T>(authorize: () throws -> Void,
                                        _ work: (POSIXArchiveWriterLease) throws -> T) throws -> T {
        guard state == .quiesced, !operationConsumed, let lease = quiescedOperationLease else {
            throw Failure.inactive
        }
        guard currentSession() == session else { throw Failure.sessionChanged }
        // A failed import may leave recovery evidence. Never silently run it again.
        operationConsumed = true
        return try gate.withArchiveRecoveryLease(lease) { archive in
            try authorize()
            guard currentSession() == session else { throw Failure.sessionChanged }
            return try work(archive)
        }
    }

    /// A closed owner's one session/reset handoff uses only its own replacement
    /// epoch, never a newly captured lease. Archive and handoff are mutually exclusive.
    func withQuiescedTransition<T>(authorize: () throws -> Void,
                                   _ work: () throws -> T) throws -> T {
        guard state == .quiesced, !operationConsumed, let lease = quiescedOperationLease else {
            throw Failure.inactive
        }
        guard currentSession() == session else { throw Failure.sessionChanged }
        operationConsumed = true
        return try gate.withWriterEffect(lease) {
            try authorize()
            guard currentSession() == session else { throw Failure.sessionChanged }
            return try work()
        }
    }

    /// Idempotent only after a successful drain. An interrupted/failed quiescence
    /// stays closed and may not be reused or treated as a publishable replacement.
    func quiesce() async throws {
        if state == .quiesced { return }
        guard state == .active else { throw Failure.inactive }
        state = .quiescing  // closes local effects and new registrations before cancellation
        var failure: Error?
        do { quiescedOperationLease = try gate.invalidateWriters(expectedLease: admittedLease) }
        catch { failure = error }
        let pending = Array(consumers.values)
        for consumer in pending { consumer.cancel() }
        // Drain all participants even when one throws. Keep the closed state on failure.
        for consumer in pending {
            do { try await consumer.drain() }
            catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
        consumers.removeAll()
        state = .quiesced
    }
}
