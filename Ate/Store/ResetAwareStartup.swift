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

    func start() async {
        guard !started else { return }
        started = true
        state = .checkingReset
        // No TimerCenter, JournalStore.shared, StoreRecovery.open, AppStore.load,
        // intent relay, widget publish/drain or ordinary Root.task may precede this.
        let outcome = await resume()
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
            try validateAdmission(lease)
            let graph = try buildGraph(lease)
            try validateAdmission(lease)
            state = .ready(graph)
        } catch JournalStartupAuthorizationError.blocked(let reason) {
            state = .blocked(.unavailable(reason))
        } catch {
            state = .failed("Ate could not verify safe startup. Your data is not ready to use.")
        }
    }
}
