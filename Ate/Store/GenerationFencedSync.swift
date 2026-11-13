import Foundation

/// Additive candidate only. No production constructor/call site until the complete
/// AppStore metadata/startup/writer fence is composed and qualified. There is deliberately
/// no direct-write fallback: the candidate SQL revokes the old client POST route.
@MainActor
final class GenerationFencedSync {
    struct Capture: Equatable {
        let ownerID: String
        let generation: Int64
        let writerLease: UUID
    }
    struct Snapshot {
        let capture: Capture
        let rows: [SyncRecord]
    }
    enum Error: Swift.Error, Equatable {
        case ownerChanged, invalidGeneration, mismatchedRowOwner, duplicateIdentity
    }

    private let rpc: AccountDataResetService
    private let currentSession: () -> AuthSession?
    /// Actual binding must check persistent reset control AND cross-process writer
    /// epoch, not merely Task cancellation. Called before and after each await.
    private let captureWriter: () throws -> UUID
    private let validateWriter: (UUID) throws -> Void

    init(rpc: AccountDataResetService, currentSession: @escaping () -> AuthSession?,
         captureWriter: @escaping () throws -> UUID,
         validateWriter: @escaping (UUID) throws -> Void) {
        self.rpc = rpc
        self.currentSession = currentSession
        self.captureWriter = captureWriter
        self.validateWriter = validateWriter
    }

    private func session(for ownerID: String, lease: UUID) throws -> AuthSession {
        try validateWriter(lease)
        guard let session = currentSession(), session.userID == ownerID else {
            throw Error.ownerChanged
        }
        return session
    }

    /// Captures rows and generation atomically at the server. The caller must compare
    /// against its persisted owner/generation BEFORE merging local rows. An advanced
    /// generation means stale local bytes must not be stamped with the fresh generation.
    func snapshot() async throws -> Snapshot {
        let lease = try captureWriter()
        try validateWriter(lease)
        guard let owner = currentSession()?.userID else { throw Error.ownerChanged }
        let result = try await rpc.snapshot(session: session(for: owner, lease: lease))
        _ = try session(for: owner, lease: lease)
        guard result.generation >= 0 else { throw Error.invalidGeneration }
        guard result.rows.allSatisfy({ $0.user_id == owner }) else { throw Error.mismatchedRowOwner }
        var identities = Set<String>()
        for row in result.rows {
            // JSON encoding removes delimiter ambiguities in kind/id.
            let identity = String(decoding: try JSONEncoder().encode([row.kind, row.id]), as: UTF8.self)
            guard identities.insert(identity).inserted else { throw Error.duplicateIdentity }
        }
        return Snapshot(capture: Capture(ownerID: owner, generation: result.generation, writerLease: lease), rows: result.rows)
    }

    /// Uses the ORIGINAL capture for every row, never a silently fetched newer epoch.
    /// Partial transport success is not a batch receipt. Any error leaves the caller
    /// needing an owner/generation-checked snapshot and normal LWW reconciliation.
    func push(_ rows: [SyncRecord], capture: Capture) async throws {
        guard capture.generation >= 0 else { throw Error.invalidGeneration }
        _ = try session(for: capture.ownerID, lease: capture.writerLease)
        guard rows.allSatisfy({ $0.user_id == capture.ownerID }) else { throw Error.mismatchedRowOwner }
        var identities = Set<String>()
        for row in rows {
            let identity = String(decoding: try JSONEncoder().encode([row.kind, row.id]), as: UTF8.self)
            guard identities.insert(identity).inserted else { throw Error.duplicateIdentity }
        }
        for row in rows {
            let live = try session(for: capture.ownerID, lease: capture.writerLease)
            try await rpc.putRecipe(session: live, callerGeneration: capture.generation,
                                    kind: row.kind, id: row.id, data: row.data?.raw,
                                    updatedAt: row.updated_at, deleted: row.deleted)
            _ = try session(for: capture.ownerID, lease: capture.writerLease)
        }
    }
}

/// Retained pull/merge/push cycle for the admitted graph. No direct-table fallback.
/// Completion/abandonment clears the capture, never promotes it to a new epoch.
@MainActor
final class GenerationFencedSyncService: SyncService {
    enum CycleError: Swift.Error { case concurrentCycle, missingPull, sessionChanged, receiptChanged, blocked }
    private let adapter: GenerationFencedSync
    private let receipt: () throws -> AccountGenerationPolicy.Receipt?
    private let invalidateWriters: () throws -> Void
    private var pending: (AuthSession, GenerationFencedSync.Capture)?
    private var inFlight = false
    private(set) var conflict: AccountGenerationConflictState?

    init(adapter: GenerationFencedSync,
         receipt: @escaping () throws -> AccountGenerationPolicy.Receipt?,
         invalidateWriters: @escaping () throws -> Void) {
        self.adapter = adapter; self.receipt = receipt; self.invalidateWriters = invalidateWriters
    }

    private func validate(_ capture: GenerationFencedSync.Capture, session: AuthSession) throws {
        guard capture.ownerID == session.userID,
              let local = try receipt(), local.ownerID == session.userID,
              local.generation == capture.generation else { throw CycleError.receiptChanged }
    }
    private func block() throws {
        pending = nil
        conflict = .staleLocalData
        // Existing graph writers immediately fail their original lease. Do not fetch
        // another lease or epoch here; activation host must keep this graph closed.
        try invalidateWriters()
    }
    func abandonCycle() { pending = nil }

    func pull(session: AuthSession) async throws -> [SyncRecord] {
        guard conflict == nil else { throw CycleError.blocked }
        guard !inFlight, pending == nil else { throw CycleError.concurrentCycle }
        inFlight = true
        defer { inFlight = false }
        do {
            let snapshot = try await adapter.snapshot()
            try validate(snapshot.capture, session: session)
            pending = (session, snapshot.capture)
            return snapshot.rows
        } catch ResetRPCError.staleGeneration {
            try block(); throw ResetRPCError.staleGeneration
        } catch CycleError.receiptChanged {
            try block(); throw ResetRPCError.staleGeneration
        }
    }
    func push(_ records: [SyncRecord], session: AuthSession) async throws {
        guard conflict == nil else { throw CycleError.blocked }
        guard !inFlight else { throw CycleError.concurrentCycle }
        guard let (originalSession, capture) = pending else { throw CycleError.missingPull }
        pending = nil // consumed even on a partial response; no implicit replay
        guard session == originalSession else { throw CycleError.sessionChanged }
        inFlight = true
        defer { inFlight = false }
        do {
            try validate(capture, session: session)
            try await adapter.push(records, capture: capture)
            try validate(capture, session: session)
        } catch ResetRPCError.staleGeneration {
            try block(); throw ResetRPCError.staleGeneration
        } catch CycleError.receiptChanged {
            try block(); throw ResetRPCError.staleGeneration
        }
    }
}
