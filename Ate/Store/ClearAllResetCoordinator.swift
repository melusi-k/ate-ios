import Foundation

/// Reset phase machine behind Settings "Clear all" (candidate, UNWIRED). Central binds:
/// - the real cross-process writer gate (ClearAllWriterGating),
/// - awaited system-surface cleanup (ClearAllSystemSurfaceCleaning),
/// - the component list (built from ClearAllLocalData primitives + ClearAllDataKeys),
/// - a durable receiptSink that persists the confirmed generation into sync metadata,
/// - a currentSession provider (owner re-checks use the CURRENT session, not a capture),
/// - and AppStore.clearAllAccountData(), whose fail-closed body this replaces.
///
/// Owner-confirmed scope (2026-11-04): account-wide wipe of every store incl. Shopping
/// and Journal; account and subscription retained. Sequencing follows
/// docs/implementation/CLEAR_ALL_RESET_PROTOCOL.md. No rollback backup: retained
/// personal bytes are user data. Control-record integrity is fail-closed: a corrupted
/// record NEVER permits a fresh reset UUID.
///
/// Gate lifetime: the gate is held only during an active attempt and released before
/// every terminal state. Resumability is anchored by the durable control record, not by
/// a held gate. Central's binding MUST therefore also refuse writes whenever a control
/// record exists, not only while the gate is held.
protocol ClearAllWriterGating {
    /// Acquires the durable gate or throws while any writer may still be active.
    func acquireResetGate() throws
    /// Re-validated before and after every await and before every component effect;
    /// throws if the gate was lost.
    func validateResetGate() throws
    func releaseResetGate()
}

/// Awaited system-surface cleanup (protocol stage 8): pending AND delivered
/// notifications, Live Activities, Spotlight entries, widget/watch snapshots and queues.
/// Returns the names of surfaces that could not be cleaned; empty means all verified.
protocol ClearAllSystemSurfaceCleaning {
    func cleanupAfterLocalErase() async -> [String]
}

enum ClearAllControlError: Error, Equatable {
    /// A stored control record exists but cannot be read back exactly. Fail closed:
    /// never issue a fresh reset UUID while durable state is in doubt.
    case corruptRecord
    case persistenceUnverified
}

@MainActor
final class ClearAllResetCoordinator {
    /// Non-personal control state, deliberately NOT in ClearAllDataKeys: preserved across
    /// the erase so a lost response can be recovered and old data can never resurrect.
    static let controlKey = "ate.clearAll.control.v1"

    enum Phase: String, Codable {
        case requested        // RPC issued or about to be; outcome unknown
        case cloudCommitted   // receipt verified; local erase pending/incomplete
    }

    /// Minimal non-personal control record. No bearer tokens, no personal data backup.
    struct ControlRecord: Codable, Equatable {
        let ownerID: String
        let requestID: UUID
        var expectedGeneration: Int64
        var phase: Phase
        var confirmedGeneration: Int64?
        var pendingComponents: [String]
    }

    private let rpc: AccountDataResetService
    private let gate: ClearAllWriterGating
    private let surfaces: ClearAllSystemSurfaceCleaning
    private let controlPersistence: ResetControlPersistence
    /// CURRENT session provider: owner checks never trust a session captured before an
    /// await, because the account may have switched mid-flight.
    private let currentSession: () -> AuthSession?
    /// Durable receipt handoff: persists the confirmed generation into sync metadata
    /// BEFORE the control record is retired. Central binds AppStore's real write.
    private let receiptSink: (Int64) throws -> Void
    private let components: () throws -> ([ClearAllLocalData.Component], Set<String>)

    init(rpc: AccountDataResetService, gate: ClearAllWriterGating,
         surfaces: ClearAllSystemSurfaceCleaning,
         controlPersistence: ResetControlPersistence,
         currentSession: @escaping () -> AuthSession?,
         receiptSink: @escaping (Int64) throws -> Void,
         components: @escaping () throws -> ([ClearAllLocalData.Component], Set<String>)) {
        self.rpc = rpc; self.gate = gate; self.surfaces = surfaces
        self.controlPersistence = controlPersistence; self.currentSession = currentSession
        self.receiptSink = receiptSink; self.components = components
    }

    /// Terminal exit: release the attempt's gate hold before reporting. Resumability
    /// lives in the control record; central's gate binding refuses writes while a
    /// record exists (see header).
    private func finish(_ state: AppStore.ClearAllState) -> AppStore.ClearAllState {
        gate.releaseResetGate()
        return state
    }

    /// Nil only when NO record is stored. A present-but-undecodable record throws
    /// corruptRecord: durable state in doubt must never allow a fresh reset UUID.
    private func loadControl() throws -> ControlRecord? {
        // Existence first: data(forKey:) returns nil for a PRESENT value of the wrong
        // type (string/bool/dict), which must fail closed, not read as "no record".
        guard let raw = try controlPersistence.read() else { return nil }
        guard let record = try? JSONDecoder().decode(ControlRecord.self, from: raw) else {
            throw ClearAllControlError.corruptRecord
        }
        // Semantic validation: a decodable but impossible record is still corrupt.
        guard !record.ownerID.isEmpty,
              record.expectedGeneration >= 0, record.expectedGeneration < Int64.max else {
            throw ClearAllControlError.corruptRecord
        }
        if record.phase == .requested, record.confirmedGeneration != nil {
            throw ClearAllControlError.corruptRecord   // a request in flight holds no receipt
        }
        if let confirmed = record.confirmedGeneration {
            guard confirmed >= 0 else { throw ClearAllControlError.corruptRecord }
        }
        if record.phase == .cloudCommitted {
            // Committed phase REQUIRES the exact receipt; never erase without it.
            guard record.confirmedGeneration == record.expectedGeneration + 1 else {
                throw ClearAllControlError.corruptRecord
            }
        }
        confirmedGeneration = record.confirmedGeneration
        return record
    }

    /// Exact readback: a reset RPC may only run once its request UUID is proven durable.
    private func saveControl(_ record: ControlRecord?) throws {
        if let record {
            let encoded = try JSONEncoder().encode(record)
            try controlPersistence.write(encoded)
            guard let back = try controlPersistence.read(),
                  (try? JSONDecoder().decode(ControlRecord.self, from: back)) == record else {
                throw ClearAllControlError.persistenceUnverified
            }
        } else {
            try controlPersistence.remove()
            // object(forKey:), not data(forKey:): a wrong-type residue reads as nil
            // through data(forKey:) and would fake a successful retirement.
            guard try controlPersistence.read() == nil else {
                throw ClearAllControlError.persistenceUnverified
            }
        }
    }

    /// The verified cloud receipt, if any; restored from the control record on load.
    /// AppStore stamps every subsequent putRecipe call with this generation.
    private(set) var confirmedGeneration: Int64?

    /// Owner check against the CURRENT session, used before and after every await.
    private func requireOwner(_ ownerID: String) throws -> AuthSession {
        // No session at all: sign-in problem. A DIFFERENT signed-in account (switch
        // mid-flight): outcome unknown for the original owner, reported unverified.
        guard let session = currentSession() else { throw ResetRPCError.unauthorized }
        guard session.userID == ownerID else {
            throw ResetRPCError.outcomeUnverified("signed-in account changed during the reset")
        }
        try gate.validateResetGate()
        return session
    }

    /// Entry behind Settings "Clear all". Never throws into the UI: every outcome is a
    /// fail-closed AppStore.ClearAllState. Account reset requires an online session;
    /// signed-out local-only reset is a separately labelled route and NOT offered here.
    func start() async -> AppStore.ClearAllState {
        // Durable state FIRST: early-exit wording must never claim "nothing has been
        // cleared" while a retained record proves a prior attempt may have committed
        // server-side (cloudCommitted or a lost response).
        // Preflight only drives wording; it is STALE the moment we wait on the gate.
        let preflight: ControlRecord?
        do { preflight = try loadControl() } catch {
            // Corrupt durable state: stop. Do NOT start a new reset over it.
            return .serverOutcomeUnverified
        }
        guard let session = currentSession() else {
            return .unavailable(preflight == nil
                                ? "Sign in to clear your ate account data."
                                : "Sign in to finish clearing your ate account data.")
        }
        do { try gate.acquireResetGate() } catch {
            // Phase-agnostic: no claim about cleared state in either direction.
            return .unavailable("ate can't clear your data right now. Try again in a moment.")
        }
        // Strict reload UNDER the gate: another holder may have committed its own
        // attempt while we waited. A stale preflight nil must never mint a fresh UUID
        // over an existing record, and corrupt state under the gate fails closed.
        let pending: ControlRecord?
        do { pending = try loadControl() } catch { return finish(.serverOutcomeUnverified) }
        if let pending { return await resume(pending) }

        // Fresh reset: resolve expectedGeneration from a snapshot, never assume it.
        do {
            let liveSession = try requireOwner(session.userID)
            let snapshot = try await rpc.snapshot(session: liveSession)
            _ = try requireOwner(session.userID)   // account switch during the await?
            let record = ControlRecord(ownerID: session.userID, requestID: UUID(),
                                       expectedGeneration: snapshot.generation,
                                       phase: .requested, confirmedGeneration: nil,
                                       pendingComponents: [])
            try saveControl(record)   // UUID proven durable BEFORE the RPC may run
            return await runCloudPhase(record, isResume: false)
        } catch let e as ResetRPCError {
            switch e {
            case .unauthorized:
                return finish(.unavailable("Sign in again to clear your ate account data. Nothing has been cleared."))
            case .contractMissing:
                return finish(.unavailable("Clear all needs an app update before it can run safely. Nothing has been cleared."))
            default:
                return finish(.serverOutcomeUnverified)
            }
        } catch {
            return finish(.serverOutcomeUnverified)
        }
    }

    /// Relaunch resume: runs BEFORE migration/recovery/seeding/sync/widget queues
    /// (protocol stage 10). Returns nil only when no reset is pending. A corrupt record
    /// does NOT count as "nothing pending": it reports unverified instead.
    func resumeIfPending() async -> AppStore.ClearAllState? {
        let record: ControlRecord?
        do { record = try loadControl() } catch { return .serverOutcomeUnverified }
        guard let record else { return nil }
        guard currentSession() != nil else {
            return .unavailable("Sign in to finish clearing your ate account data.")
        }
        do { try gate.acquireResetGate() } catch {
            return .unavailable("ate can't continue clearing your data right now. Try again in a moment.")
        }
        // Same race as start(): re-read under the gate. If another holder retired the
        // record, its attempt completed - nothing is pending anymore.
        let current: ControlRecord?
        do { current = try loadControl() } catch { return finish(.serverOutcomeUnverified) }
        guard let current else { gate.releaseResetGate(); return nil }
        return await resume(current)
    }

    private func resume(_ record: ControlRecord) async -> AppStore.ClearAllState {
        do { _ = try requireOwner(record.ownerID) } catch { return finish(.serverOutcomeUnverified) }
        switch record.phase {
        case .requested:
            // Lost response recovery: retry the SAME request UUID. The RPC is idempotent
            // for it, and rejects it if a later distinct reset already happened.
            return await runCloudPhase(record, isResume: true)
        case .cloudCommitted:
            return await runLocalPhase(record)
        }
    }

    /// isResume distinguishes a record created moments ago in THIS process (its RPC
    /// provably never ran if the contract 404s) from a retained record whose earlier
    /// attempt may have committed while the contract still existed.
    private func runCloudPhase(_ record: ControlRecord, isResume: Bool) async -> AppStore.ClearAllState {
        do {
            let session = try requireOwner(record.ownerID)
            let generation = try await rpc.clearAccount(session: session,
                requestID: record.requestID, expectedGeneration: record.expectedGeneration)
            _ = try requireOwner(record.ownerID)   // account switch during the await?
            var next = record
            next.phase = .cloudCommitted
            next.confirmedGeneration = generation
            try saveControl(next)   // receipt durable BEFORE the local phase and any write
            confirmedGeneration = generation
            return await runLocalPhase(next)
        } catch let e as ResetRPCError {
            switch e {
            case .staleGeneration:
                // The account moved past expectedGeneration: either a later DISTINCT reset
                // (ours is dead) or our own request already committed elsewhere. Keep the
                // control record and stop at unverified: CENTRAL's binding resolves which
                // via a snapshot check before resuming. Never start a fresh request UUID
                // automatically (protocol stage 6).
                return finish(.serverOutcomeUnverified)
            case .unauthorized:
                return finish(.unavailable("Sign in again to finish clearing your ate account data."))
            case .contractMissing:
                if isResume {
                    // A prior attempt may have committed while the contract existed;
                    // its absence NOW proves nothing. Keep the record, stay unverified.
                    return finish(.serverOutcomeUnverified)
                }
                // Fresh attempt: the 404 proves this reset never ran, so the record can
                // retire - but if that retirement itself fails, the durable state is in
                // doubt: unverified.
                do { try saveControl(nil) } catch { return finish(.serverOutcomeUnverified) }
                return finish(.unavailable("Clear all needs an app update before it can run safely. Nothing has been cleared."))
            default:
                // Response possibly lost AFTER commit: keep the control record, report
                // unverified, resume on next launch/attempt with the same request UUID.
                return finish(.serverOutcomeUnverified)
            }
        } catch {
            // Control-record persistence failed mid-phase, or an unexpected transport
            // error: durable state in doubt, report unverified, keep the record.
            return finish(.serverOutcomeUnverified)
        }
    }

    private func runLocalPhase(_ record: ControlRecord) async -> AppStore.ClearAllState {
        // Receipt gate FIRST: no local effect may run for a committed-phase record
        // that does not carry its exact verified receipt.
        guard let generation = record.confirmedGeneration,
              generation == record.expectedGeneration + 1 else {
            return finish(.serverOutcomeUnverified)
        }
        do {
            _ = try requireOwner(record.ownerID)
            let (components, required) = try components()
            let report = try ClearAllLocalData.execute(components, requiredNames: required,
                                                       validateWriterGate: gate.validateResetGate)
            guard report.complete else {
                var pending = record
                pending.pendingComponents = report.failures.map(\.component)
                try saveControl(pending)   // record kept; idempotent retry resumes here
                return finish(.cloudCommittedLocalIncomplete(report.failures.map(\.component)))
            }
            let uncleaned = await surfaces.cleanupAfterLocalErase()
            _ = try requireOwner(record.ownerID)
            guard uncleaned.isEmpty else {
                var pending = record
                pending.pendingComponents = uncleaned
                try saveControl(pending)
                return finish(.cloudCommittedLocalIncomplete(uncleaned))
            }
            // Receipt handoff BEFORE the control record is retired: a crash between the
            // two must never lose the generation future writes depend on. If the sink
            // throws, the record stays and resume replays this idempotent phase. A sink
            // failure is NOT a local-erase failure: the erase already completed, so the
            // honest state is unverified, never cloudCommittedLocalIncomplete.
            do { try receiptSink(generation) } catch { return finish(.serverOutcomeUnverified) }
            try saveControl(nil)
            return finish(.completed)
        } catch let e as ResetRPCError {
            // Owner/session lost mid-phase (account switch): never report component
            // progress against the wrong account.
            _ = e
            return finish(.serverOutcomeUnverified)
        } catch ClearAllControlError.corruptRecord, ClearAllControlError.persistenceUnverified {
            // Durable control state could not be written/read back exactly: stop and
            // report unverified rather than a guessed component list.
            return finish(.serverOutcomeUnverified)
        } catch {
            return finish(.cloudCommittedLocalIncomplete(record.pendingComponents.isEmpty
                                                         ? ["local data"] : record.pendingComponents))
        }
    }
}
