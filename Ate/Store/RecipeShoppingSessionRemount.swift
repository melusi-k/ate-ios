import Foundation

/// Dormant lifecycle coordinator. Owner factory and graph builder are injected, but
/// full-session persistence is throwing and verified, never Keychain try?-success.
/// Production factory must use the same current-session source as every owner.
@MainActor
final class RecipeShoppingSessionRemount<Graph> {
    enum State { case idle, checking, signedOut, failed(String), ready(Graph) }
    enum Refusal: Error { case retired, sessionChanged, foreignOwner, persistenceUnverified, invalidRefreshedSession }
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
    private func refreshedSession(_ previous: AuthSession, run: UUID, now: Date) async throws -> AuthSession? {
        do {
            let refreshed = try await auth.refresh(previous)
            try validate(run, session: previous)
            guard refreshed.userID == previous.userID, !refreshed.userID.isEmpty else { throw Refusal.foreignOwner }
            guard refreshed.expiresAt > now.timeIntervalSince1970 + 30 else { throw Refusal.invalidRefreshedSession }
            try persistSession(refreshed)
            guard currentSession() == refreshed else { throw Refusal.persistenceUnverified }
            return refreshed
        } catch let error as AuthError where error.kind == .unauthorized {
            try validate(run, session: previous)
            try persistSession(nil)
            guard currentSession() == nil else { throw Refusal.persistenceUnverified }
            return nil // local data untouched; no erase/reset
        }
    }
    private func admit(_ session: AuthSession, run: UUID) async throws -> RecipeShoppingSyncOwner {
        try validate(run, session: session)
        let candidate = try makeOwner(session)
        owner = candidate // retained so retire() invalidates suspended admission
        _ = try await candidate.pull(session: session)
        try validate(run, session: session)
        // Consume snapshot capture without uploading data. No put retry/replay.
        try await candidate.push([], session: session)
        try validate(run, session: session)
        return candidate
    }
    func start(now: Date = Date(), forceRefresh: Bool = false) async {
        guard !running, !terminal else { return }
        running = true
        defer { running = false }
        let run = UUID(); token = run; state = .checking
        let expected = currentSession()
        do {
            try validate(run, session: expected)
            try owner?.retireForSessionTransition(); owner = nil
            guard var session = expected else { state = .signedOut; return }
            var didRefresh = false
            if forceRefresh || session.expiresAt < now.timeIntervalSince1970 + 60 {
                guard let refreshed = try await refreshedSession(session, run: run, now: now) else {
                    state = .signedOut; return
                }
                session = refreshed; didRefresh = true
            }
            let candidate: RecipeShoppingSyncOwner
            do {
                candidate = try await admit(session, run: run)
            } catch ResetRPCError.unauthorized {
                // A still-unexpired token can be rejected. Exactly one explicit
                // refresh and a wholly NEW owner/snapshot, never reuse its capture.
                // 403/42501/PT409 do not enter this branch. A second401 stops.
                try validate(run, session: session)
                try owner?.retireForSessionTransition(); owner = nil
                guard !didRefresh else { throw ResetRPCError.unauthorized }
                guard let refreshed = try await refreshedSession(session, run: run, now: now) else {
                    state = .signedOut; return
                }
                session = refreshed
                candidate = try await admit(session, run: run)
            }
            let graph = try buildGraph(candidate, session)
            try validate(run, session: session)
            state = .ready(graph)
        } catch {
            try? owner?.retireForSessionTransition(); owner = nil
            if token == run && !terminal { state = .failed(error.localizedDescription) }
        }
    }
}
