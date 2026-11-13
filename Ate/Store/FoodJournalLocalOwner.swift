import Foundation
import SwiftData

/// Dormant local owner. Uses the existing shared account gate and archive generation
/// chain, not a second lock or an independently captured replacement writer lease.
/// Container opening/recovery and identity admission must finish before this call.
@MainActor
final class FoodJournalLocalOwner {
    struct Locations {
        let storeFileURL: URL
        let mediaDirectory: URL
        let migrationBackupDirectory: URL
        let repairBackupDirectory: URL
        let preservationDirectory: URL
    }
    enum Failure: Error { case invalidLocations, storeConfigurationMismatch }

    let runtime: FoodJournalRuntime
    let locations: Locations
    private let gate: AccountWriterGate
    private let lease: UUID
    private let validateConsumers: () throws -> Void

    private init(runtime: FoodJournalRuntime, locations: Locations,
                 gate: AccountWriterGate, lease: UUID, validateConsumers: @escaping () throws -> Void) {
        self.runtime = runtime
        self.locations = locations
        self.gate = gate
        self.lease = lease
        self.validateConsumers = validateConsumers
    }

    static func bind(container: ModelContainer?, openState: JournalOpenState,
                     defaults: UserDefaults, goalsStorage: NutritionGoalsStorage,
                     locations: Locations, gate: AccountWriterGate, admittedLease: UUID,
                     archive: ArchiveNestedLeaseBoundary,
                     afterRestoreCommit: @escaping () throws -> Void,
                     validateConsumers: @escaping () throws -> Void = {}) throws -> FoodJournalLocalOwner {
        // Refuse before construction under the original admission, including pending
        // reset and stale identity epochs. No captureWriter or disk reopen here.
        try gate.withWriterEffect(admittedLease) {
            try validateConsumers()
            let directories = [locations.mediaDirectory, locations.migrationBackupDirectory,
                               locations.repairBackupDirectory, locations.preservationDirectory]
            let all = directories + [locations.storeFileURL]
            guard all.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") && $0.path != "/" && $0 == $0.standardizedFileURL }),
                  Set(all).count == all.count,
                  !directories.contains(where: { parent in
                      all.contains { child in parent != child && child.path.hasPrefix(parent.path + "/") }
                  }) else { throw Failure.invalidLocations }
            // Inventory and the actual single persisted configuration must agree.
            guard let container, container.configurations.count == 1,
                  container.configurations.first?.url.standardizedFileURL == locations.storeFileURL else {
                throw Failure.storeConfigurationMismatch
            }
            let perform = JournalWriterBoundaryComposition.makePerform(
                gate: gate, writerLease: admittedLease, archive: archive)
            let boundary = FoodJournalWriterBoundary(perform: { effect in
                try gate.withWriterEffect(admittedLease) {
                    try validateConsumers()
                    try perform(effect)
                }
            })
            let runtime = try FoodJournalRuntimeFactory.bind(container: container, openState: openState,
                bindings: .init(defaults: defaults,
                    goals: NutritionGoalsRepository(defaults: defaults, storage: goalsStorage, writerBoundary: boundary),
                    writerBoundary: boundary, mediaDirectory: locations.mediaDirectory,
                    migrationBackupDirectory: locations.migrationBackupDirectory,
                    repairBackupDirectory: locations.repairBackupDirectory,
                    afterRestoreCommit: afterRestoreCommit))
            return FoodJournalLocalOwner(runtime: runtime, locations: locations, gate: gate, lease: admittedLease, validateConsumers: validateConsumers)
        }
    }

    func requireLifecycle(_ lifecycle: FoodJournalConsumerLifecycle) throws {
        guard lifecycle.belongs(to: gate, lease: lease) else { throw AccountWriterGate.Error.staleLease }
        try validate()
        try lifecycle.validate()
    }

    /// Validation does not enter archive mutation or advance its generation.
    func validate() throws {
        try gate.withWriterEffect(lease) { try validateConsumers() }
    }

    /// Exact same storage inventory as this owner's runtime. The caller must separately
    /// quiesce all consumers and hold its authorized reset/account-action boundary.
    var resetInventory: JournalLocalReset {
        JournalLocalReset(journal: runtime.journal, defaults: runtime.defaults,
            goalsStorage: runtime.goalsRepository.storage,
            mediaDirectory: locations.mediaDirectory,
            migrationBackupDirectory: locations.migrationBackupDirectory,
            repairBackupDirectory: locations.repairBackupDirectory,
            preservationDirectory: locations.preservationDirectory,
            storeFileURL: locations.storeFileURL)
    }
}
