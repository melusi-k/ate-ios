import Foundation
import Observation

enum JournalStartupAuthorizationError: Error {
    case blocked(String)
}

/// Candidate owner of LAZY ordinary AppStore construction. The resume closure may
/// construct reset primitives/empty contexts, never ordinary migrating/seeding stores.
/// No production call site yet. Admission must be the real cross-process writer lease.
@Observable
@MainActor
final class ResetAwareStartup<Graph> {
    enum State {
        case notStarted
        case checkingReset
        case blocked(AppStore.ClearAllState)
        case failed(String)
        case ready(Graph)
    }
    private(set) var state: State = .notStarted
    private let resume: () async -> AppStore.ClearAllState?
    private let captureAdmission: () throws -> UUID
    private let authorizeAdmission: (UUID) async throws -> Void
    private let validateAdmission: (UUID) throws -> Void
    private let buildGraph: (UUID) throws -> Graph
    private var started = false
    private var runID = UUID()

    init(resume: @escaping () async -> AppStore.ClearAllState?,
         captureAdmission: @escaping () throws -> UUID,
         validateAdmission: @escaping (UUID) throws -> Void,
         authorizeAdmission: @escaping (UUID) async throws -> Void = { _ in },
         buildGraph: @escaping (UUID) throws -> Graph) {
        self.resume = resume
        self.captureAdmission = captureAdmission
        self.validateAdmission = validateAdmission
        self.authorizeAdmission = authorizeAdmission
        self.buildGraph = buildGraph
    }

    /// Retires the mounted graph and invalidates all currently suspended admission
    /// work. This is NOT writer quiescence: caller must block the durable gate first
    /// and stop every producer. There is no restart API; a new owner must reconcile
    /// afresh before admitting a replacement graph. Stale resume/snapshot completions
    /// cannot overwrite this terminal block, even when their task ignores cancellation.
    func retire(reason: AppStore.ClearAllState) {
        runID = UUID()
        started = true
        state = .blocked(reason)
    }

    func start() async {
        guard !started else { return }
        started = true
        let capturedRun = runID
        state = .checkingReset
        // No TimerCenter, JournalStore.shared, StoreRecovery.open, AppStore.load,
        // intent relay, widget publish/drain or ordinary Root.task may precede this.
        let outcome = await resume()
        guard runID == capturedRun else { return }
        if let outcome, outcome != .completed {
            state = .blocked(outcome)
            return
        }
        do {
            // Admission rechecks retained control after resume and atomically enters
            // the ordinary writer generation, closing the resume/build gap.
            let lease = try captureAdmission()
            try validateAdmission(lease)
            // Remote reconciliation must not run under an OS flock. Its final
            // adoption write reacquires the common gate and rechecks every input.
            try await authorizeAdmission(lease)
            guard runID == capturedRun else { return }
            try validateAdmission(lease)
            let graph = try buildGraph(lease)
            try validateAdmission(lease)
            guard runID == capturedRun else { return }
            state = .ready(graph)
        } catch JournalStartupAuthorizationError.blocked(let reason) {
            guard runID == capturedRun else { return }
            state = .blocked(.unavailable(reason))
        } catch {
            guard runID == capturedRun else { return }
            state = .failed("Ate could not verify safe startup. Your data is not ready to use.")
        }
    }
}
