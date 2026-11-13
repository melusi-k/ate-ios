import Foundation
import UserNotifications

/// One owner's ordered OS work. Closing prevents new submissions; draining waits
/// for even cancellation-ignoring OS adds before account cleanup removes anything.
@MainActor
final class OrderedTimerNotifications {
    private var tail: Task<Void, Never>?
    private var closed = false
    private let validate: () throws -> Void
    private let add: (UNNotificationRequest) async throws -> Void
    private let remove: ([String]) -> Void

    init(validate: @escaping () throws -> Void = {},
         add: @escaping (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) },
         remove: @escaping ([String]) -> Void = { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) }) {
        self.validate = validate; self.add = add; self.remove = remove
    }
    func closeOwner() { closed = true }
    func drainOwner() async { await tail?.value }
    func schedule(_ request: UNNotificationRequest) {
        enqueue {
            try self.validate()
            self.remove([request.identifier])
            try await self.add(request)
            if self.closed || (try? self.validate()) == nil { self.remove([request.identifier]) }
        }
    }
    func cancel(_ id: String) { enqueue { self.remove([id]) } }
    private func enqueue(_ work: @escaping () async throws -> Void) {
        guard !closed else { return }
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            guard !self.closed else { return }
            try? await work()
        }
    }
}
