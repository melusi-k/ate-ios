import Foundation

/// Watch-side counterpart of FoodJournalWriterBoundary (#245, lane 3). Same seam shape:
/// a synchronous, exactly-once, non-escaping effect boundary - plus a writer epoch so a
/// result produced before a network await can be fenced off after it. The watch cannot
/// hold the phone's cross-process flock, so the production boundary fences on the watch
/// session epoch instead: a session change or sign-out invalidates in-flight work.
///
/// `.legacy` preserves today's behavior exactly: effects run inline, the epoch never
/// changes and every validation passes. Production watch wiring injects a real boundary
/// before ordinary use.
final class WatchWriterBoundary {
    enum Failure: Error { case effectNotPerformed, repeatedEffect, staleEpoch }
    private let lock = NSRecursiveLock()
    private var active = false
    private var epoch = UUID()
    private let performsEpochChecks: Bool
    private let perform: (() throws -> Void) throws -> Void

    init(perform: @escaping (() throws -> Void) throws -> Void, epochChecks: Bool = true) {
        self.perform = perform
        self.performsEpochChecks = epochChecks
    }

    /// Existing call graphs only. Production startup must inject its real boundary.
    static let legacy = WatchWriterBoundary(perform: { try $0() }, epochChecks: false)

    /// The callback must run exactly once, synchronously, and never suspend or escape.
    func withEffect<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if active { return try work() }
        var result: T?
        var performed = false
        try perform {
            guard !performed else { throw Failure.repeatedEffect }
            performed = true
            active = true
            defer { active = false }
            result = .some(try work())
        }
        guard performed, let result else { throw Failure.effectNotPerformed }
        return result
    }

    /// Captured before a network await; validated after it. Legacy captures a constant.
    func captureEpoch() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    /// Called inside the effect that changes the session (setSession / signOut / apply).
    /// Legacy is a no-op, so activation-off behavior is unchanged.
    func invalidateEpoch() {
        lock.lock()
        defer { lock.unlock() }
        if performsEpochChecks { epoch = UUID() }
    }

    /// Post-await fence: a stale result must never be applied after the session moved on.
    func validateEpoch(_ captured: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if performsEpochChecks, captured != epoch { throw Failure.staleEpoch }
    }

    /// Token refresh may legitimately advance the session epoch. Fence the GET
    /// against the epoch AFTER obtaining that token, not its superseded epoch.
    @MainActor
    func publishAfterToken<Token, Value>(
        token: () async -> Token?,
        isCurrentToken: (Token) -> Bool,
        fetch: (Token) async throws -> Value,
        publish: (Value) throws -> Void
    ) async throws {
        guard let token = await token(), isCurrentToken(token) else { return }
        let captured = captureEpoch()
        let value = try await fetch(token)
        try validateEpoch(captured)
        try withEffect { try publish(value) }
    }

}
