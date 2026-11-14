import Foundation

/// Tasks belong to one admitted graph, never to a mutable global validator.
/// Registration completes synchronously before work can start. Quiescence cancels
/// every task and awaits its actual result, including cancellation-ignoring work.
@MainActor
final class FoodJournalConsumerTasks {
    private let lifecycle: FoodJournalConsumerLifecycle
    private let sharedBoundary: SharedWriterBoundary
    init(lifecycle: FoodJournalConsumerLifecycle, sharedBoundary: SharedWriterBoundary = .current) {
        self.lifecycle = lifecycle; self.sharedBoundary = sharedBoundary
    }

    private final class Record<Value> {
        var task: Task<Value, Error>?
    }

    private func start<Value>(_ operation: @escaping @MainActor () async throws -> Value)
        throws -> (UUID, Task<Value, Error>) {
        let record = Record<Value>()
        let id = try lifecycle.register(cancel: { record.task?.cancel() }, drain: {
            // Awaiting result is deliberate: cancellation alone is not a drain.
            if let task = record.task { _ = await task.result }
        })
        let task = Task { @MainActor [lifecycle, sharedBoundary] in
            try await SharedWriterBoundary.withCapturedOwner(sharedBoundary, operation: {
                try Task.checkCancellation()
                try lifecycle.validate()
                let value = try await operation()
                try Task.checkCancellation()
                try lifecycle.validate()
                return value
            })
        }
        record.task = task
        return (id, task)
    }

    func run<Value>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let (id, task) = try start(operation)
        defer { lifecycle.finishedConsumer(id) }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: { task.cancel() })
    }

    /// Fire-and-forget at the call site, but not at the owner boundary. The
    /// lifecycle retains/drains it; completion removes the completed registration.
    func launch(_ operation: @escaping @MainActor () async throws -> Void) throws {
        let (id, task) = try start(operation)
        Task { @MainActor [lifecycle] in
            _ = await task.result
            lifecycle.finishedConsumer(id)
        }
    }
}
