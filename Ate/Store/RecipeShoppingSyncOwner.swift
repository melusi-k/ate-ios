import Foundation

/// Dormant slice1. No ordinary launch call site until staged publication, auth/error
/// handling, legacy preservation/adoption and all writer bindings are reviewed.
/// This owner NEVER creates a receipt, resets, switches accounts or deletes data.
@MainActor
final class RecipeShoppingSyncOwner: SyncService {
    enum Refusal: Error, Equatable {
        case sessionChanged, receiptMissing, ownerMismatch, generationMismatch
        case invalidRow, concurrentCycle, missingSnapshot, admissionRequired, abandonedCycle
    }

    @MainActor private final class CycleState { var token: UUID? }
    private let cycle: CycleState
    private let gate: AccountWriterGate
    private let receipts: AccountGenerationReceiptStore
    private let session: AuthSession
    private let currentSession: () -> AuthSession?
    private let lease: UUID
    private let adapter: GenerationFencedSync
    private var admitted: AccountGenerationPolicy.Receipt?
    private var pending: GenerationFencedSync.Capture?
    private var inFlight = false

    /// Explicit, pre-provisioned real shared directory; no fallback or test lease.
    /// The factory must be retained before local load/normalization, not installed
    /// after AppStore has already made ordinary launch writes. That wiring is pending.
    init(controlDirectory: URL, rpc: AccountDataResetService,
         session: AuthSession, currentSession: @escaping () -> AuthSession?) throws {
        let control = FileResetControlPersistence(directory: controlDirectory)
        _ = try control.read()
        let receipts = try AccountGenerationReceiptStore(directory: controlDirectory)
        let gate = try AccountWriterGate(directory: controlDirectory,
            resetControlExists: { try control.read() != nil })
        let lease = try gate.captureWriter()
        guard !session.userID.isEmpty, currentSession() == session else { throw Refusal.sessionChanged }
        let cycle = CycleState()
        self.cycle = cycle
        self.gate = gate; self.receipts = receipts
        self.session = session; self.currentSession = currentSession; self.lease = lease
        // Always return the original lease. A fresh lease after a lifecycle change
        // would turn a stale graph into a new owner without construction/admission.
        self.adapter = GenerationFencedSync(rpc: rpc, currentSession: currentSession,
            captureWriter: { lease }, validateWriter: { candidate in
                try Task.checkCancellation()
                guard cycle.token != nil else { throw Refusal.abandonedCycle }
                guard candidate == lease, currentSession() == session else { throw Refusal.sessionChanged }
                try gate.validateWriter(lease)
            })
    }

    private func validate(session candidate: AuthSession) throws -> AccountGenerationPolicy.Receipt {
        guard candidate == session, currentSession() == session else { throw Refusal.sessionChanged }
        return try gate.withWriterEffect(lease) {
            guard let receipt = try receipts.read() else { throw Refusal.receiptMissing }
            guard receipt.ownerID == session.userID else { throw Refusal.ownerMismatch }
            return receipt
        }
    }

    /// Row identity is (kind,id). A recipe and shopping row may share an id;
    /// same-kind duplicates or a payload with a different id are never accepted.
    private func validateRows(_ rows: [SyncRecord]) throws {
        var identities = Set<Data>()
        for row in rows {
            guard row.user_id == session.userID, !row.id.isEmpty, row.updated_at >= 0,
                  row.kind == "recipe" || row.kind == "shopping",
                  identities.insert(try JSONEncoder().encode([row.kind, row.id])).inserted else {
                throw Refusal.invalidRow
            }
            // Tombstones carry identity/stamp, not a live payload. Existing server
            // tombstones may retain prior data, so do not invent a nil-only rule.
            if row.deleted { continue }
            guard let data = row.data?.raw else { throw Refusal.invalidRow }
            if row.kind == "recipe" {
                guard let card = try? JSONDecoder().decode(RecipeCard.self, from: data), card.id == row.id else {
                    throw Refusal.invalidRow
                }
            } else {
                guard let item = try? JSONDecoder().decode(ShoppingItem.self, from: data), item.id == row.id,
                      item.quantity.isFinite else { throw Refusal.invalidRow }
            }
        }
    }

    func pull(session candidate: AuthSession) async throws -> [SyncRecord] {
        guard !inFlight, pending == nil else { throw Refusal.concurrentCycle }
        inFlight = true
        defer { inFlight = false }
        admitted = nil
        let token = UUID()
        cycle.token = token
        do {
            try requireCycle(token)
            // Refuse unknown/foreign local owner before any network or merge. Legacy
            // no-receipt adoption needs a separate verified preservation slice.
            let before = try validate(session: candidate)
            let snapshot = try await adapter.snapshot()
            try requireCycle(token)
            let after = try validate(session: candidate)
            guard before == after, snapshot.capture.generation == after.generation else {
                throw Refusal.generationMismatch
            }
            try validateRows(snapshot.rows)
            admitted = after
            pending = snapshot.capture
            return snapshot.rows
        } catch {
            invalidateCycle()
            throw error
        }
    }

    func push(_ records: [SyncRecord], session candidate: AuthSession) async throws {
        guard !inFlight else { throw Refusal.concurrentCycle }
        guard let capture = pending, let token = cycle.token else {
            invalidateCycle(); throw Refusal.missingSnapshot
        }
        pending = nil // never replay a partial upload under an implicit fresh capture
        inFlight = true
        defer { inFlight = false }
        do {
            try requireCycle(token)
            let receipt = try validate(session: candidate)
            guard receipt == admitted, receipt.generation == capture.generation else {
                throw Refusal.generationMismatch
            }
            try validateRows(records) // whole batch is checked before the first put
            try await adapter.push(records, capture: capture)
            try requireCycle(token)
            guard try validate(session: candidate) == receipt else { throw Refusal.generationMismatch }
            cycle.token = nil
        } catch {
            invalidateCycle()
            throw error
        }
    }

    /// Actual local mutation, not validation-only. Final composition must bind all
    /// covered recipe/shopping effects here before load. This API is not installed.
    func withAdmittedWriterEffect<T>(_ effect: () throws -> T) throws -> T {
        do {
            try Task.checkCancellation()
            guard let proof = admitted else { throw Refusal.admissionRequired }
            return try gate.withWriterEffect(lease) {
                guard try validate(session: session) == proof else { throw Refusal.generationMismatch }
                return try effect()
            }
        } catch {
            invalidateCycle()
            throw error
        }
    }

    private func requireCycle(_ token: UUID) throws {
        try Task.checkCancellation()
        guard cycle.token == token else { throw Refusal.abandonedCycle }
    }
    private func invalidateCycle() {
        cycle.token = nil; pending = nil; admitted = nil
    }

    /// Invalidates in-flight adapter validation as well as returned captures.
    /// Concurrent-cycle refusal alone preserves the current cycle; every other
    /// refusal/cancellation/abandonment revokes admitted local writer capability.
    func abandonCycle() { invalidateCycle() }
}
