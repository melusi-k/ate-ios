import Foundation

/// Dormant lifecycle coordinator. Owner factory and graph builder are injected, but
/// full-session persistence is throwing and verified, never Keychain try?-success.
/// Production factory must use the same current-session source as every owner.
@MainActor
final class RecipeShoppingSessionRemount<Graph> {
    enum State { case idle, checking, signedOut, failed(String), ready(Graph) }
    enum Refusal: Error { case retired, sessionChanged, foreignOwner, persistenceUnverified }
    private(set) var state: State = .idle
    private let auth: AuthService
    private let currentSession: () -> AuthSession?
    private let persistSession: (AuthSession?) throws -> Void
    private let makeOwner: (AuthSession) throws -> RecipeShoppingSyncOwner
    private let buildGraph: (RecipeShoppingSyncOwner, AuthSession) throws -> Graph
    private var owner: RecipeShoppingSyncOwner?
    private var token = UUID()
    private var running = false
    private var terminal = false

    init(auth: AuthService, priorOwner: RecipeShoppingSyncOwner?,
         currentSession: @escaping () -> AuthSession?, persistSession: @escaping (AuthSession?) throws -> Void,
         makeOwner: @escaping (AuthSession) throws -> RecipeShoppingSyncOwner,
         buildGraph: @escaping (RecipeShoppingSyncOwner, AuthSession) throws -> Graph) {
        self.auth = auth; self.owner = priorOwner; self.currentSession = currentSession
        self.persistSession = persistSession; self.makeOwner = makeOwner; self.buildGraph = buildGraph
    }
    private func validate(_ expected: UUID, session: AuthSession?) throws {
        try Task.checkCancellation()
        guard token == expected, !terminal else { throw Refusal.retired }
        guard currentSession() == session else { throw Refusal.sessionChanged }
    }
    /// Explicit terminal retirement; no late refresh/snapshot result may publish.
    func retire() throws {
        terminal = true; token = UUID(); state = .failed("Sync graph retired; fresh admission is required.")
        try owner?.retireForSessionTransition()
        owner = nil
    }
    func start(now: Date = Date()) async {
        guard !running, !terminal else { return }
        running = true
        defer { running = false }
        let run = UUID(); token = run; state = .checking
        var expected = currentSession()
        do {
            try validate(run, session: expected)
            // No replacement can reuse the old epoch, including same-owner refresh.
            try owner?.retireForSessionTransition(); owner = nil
            guard var session = expected else { state = .signedOut; return }
            if session.expiresAt < now.timeIntervalSince1970 + 60 {
                do {
                    let refreshed = try await auth.refresh(session)
                    try validate(run, session: expected)
                    guard refreshed.userID == session.userID, !refreshed.userID.isEmpty else { throw Refusal.foreignOwner }
                    try persistSession(refreshed)
                    guard currentSession() == refreshed else { throw Refusal.persistenceUnverified }
                    expected = refreshed; session = refreshed
                } catch let error as AuthError where error.kind == .unauthorized {
                    try validate(run, session: expected)
                    try persistSession(nil)
                    guard currentSession() == nil else { throw Refusal.persistenceUnverified }
                    state = .signedOut // local data is untouched; no erase or reset
                    return
                }
            }
            try validate(run, session: session)
            let candidate = try makeOwner(session)
            owner = candidate // retained so retire() invalidates suspended admission
            _ = try await candidate.pull(session: session)
            try validate(run, session: session)
            // Consume snapshot capture without uploading data; keep admission proof.
            try await candidate.push([], session: session)
            try validate(run, session: session)
            let graph = try buildGraph(candidate, session)
            try validate(run, session: session)
            state = .ready(graph)
        } catch {
            // A retire call already owns the terminal state. Do not overwrite it
            // with a late cancelled/failed result from this run.
            try? owner?.retireForSessionTransition(); owner = nil
            if token == run && !terminal { state = .failed(error.localizedDescription) }
        }
    }
}
