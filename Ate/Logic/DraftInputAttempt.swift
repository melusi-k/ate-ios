import Foundation

/// Latest selected input wins even when a loader ignores cancellation.
/// Invalidate before discard/save or changing the draft a loaded cover belongs to.
@MainActor
final class DraftInputAttempt {
    private var token: UUID?
    private var task: Task<Void, Never>?

    func invalidate() {
        token = nil
        task?.cancel()
        task = nil
    }

    func start<Value>(load: @escaping @MainActor () async -> Value,
                      apply: @escaping @MainActor (Value) -> Void) {
        invalidate()
        let value = UUID()
        token = value
        task = Task { @MainActor [weak self] in
            let result = await load()
            guard let self, self.token == value, !Task.isCancelled else { return }
            apply(result)
            guard self.token == value else { return }
            self.task = nil
        }
    }
}
