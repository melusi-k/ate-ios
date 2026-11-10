import Foundation

/// Synchronous effect boundary shared by the Journal, archive and account owner.
/// Production composition supplies the common cross-process lock and epoch checks.
/// The callback must run exactly once, synchronously, and never suspend or escape.
final class FoodJournalWriterBoundary {
    enum Failure: Error { case effectNotPerformed, repeatedEffect }
    private let lock = NSRecursiveLock()
    private var active = false
    private let perform: (() throws -> Void) throws -> Void

    init(perform: @escaping (() throws -> Void) throws -> Void) {
        self.perform = perform
    }

    /// Existing test/legacy graphs only. Canonical production startup must inject its
    /// real cooperative account/archive boundary before any ordinary constructors.
    static let legacy = FoodJournalWriterBoundary { try $0() }

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
}
