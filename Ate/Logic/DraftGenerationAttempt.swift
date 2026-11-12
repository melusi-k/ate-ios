import Foundation

/// Own primary generation and spread children. Cancellation alone cannot revoke
/// an uncooperative backend callback; every post-await effect also needs its token.
@MainActor
final class DraftGenerationAttempt {
    private var token: UUID?
    private var task: Task<Void, Never>?
    private var children: [UUID: Task<Void, Never>] = [:]
    var isRunning: Bool { task != nil }

    func isCurrent(_ value: UUID) -> Bool { token == value && !Task.isCancelled }

    @discardableResult
    func publish(_ value: UUID, _ write: () -> Void) -> Bool {
        guard isCurrent(value) else { return false }
        write()
        return true
    }

    func invalidate() {
        token = nil
        task?.cancel(); task = nil
        for child in children.values { child.cancel() }
        children.removeAll()
    }

    func start(_ work: @escaping @MainActor (UUID) async -> Void) {
        guard !isRunning else { return }
        invalidate()
        let value = UUID()
        token = value
        task = Task { @MainActor [weak self] in
            guard let self, self.isCurrent(value) else { return }
            await work(value)
            guard self.token == value else { return }
            self.task = nil
            // Retain admission for spread children until discard/disappear or
            // the next primary attempt, even after the first review card arrives.
        }
    }

    func startChild(_ value: UUID, _ work: @escaping @MainActor () async -> Void) {
        guard isCurrent(value) else { return }
        let id = UUID()
        children[id] = Task { @MainActor [weak self] in
            guard self?.isCurrent(value) == true else { return }
            await work()
            self?.children.removeValue(forKey: id)
        }
    }
}
