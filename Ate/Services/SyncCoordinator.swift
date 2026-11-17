import Foundation
import Observation

/// First extraction seam for #499. AppStore remains the public facade and the only
/// writer of domain data. The coordinator owns sync lifecycle state and remote I/O;
/// account/epoch checks still surround awaits in AppStore before any merge publishes.
@MainActor @Observable
final class SyncCoordinator {
    var state: SyncState = .signedOut
    var scheduledTask: Task<Void, Never>?
    var inFlight = false
    var requestedWhileBusy = false

    func pull(using service: SyncService, session: AuthSession) async throws -> [SyncRecord] {
        try await service.pull(session: session)
    }

    func push(_ records: [SyncRecord], using service: SyncService, session: AuthSession) async throws {
        try await service.push(records, session: session)
    }
}
