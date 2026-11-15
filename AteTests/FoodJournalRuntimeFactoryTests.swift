import XCTest
import SwiftData
@testable import Ate

@MainActor
final class FoodJournalRuntimeFactoryTests: XCTestCase {
    enum Denied: Error { case owner }
    private func fixture(_ body: (URL, UserDefaults, ModelContainer) throws -> Void) throws {
        let suite = "Factory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
        container.mainContext.autosaveEnabled = false
        try body(root, defaults, container)
    }
    private func bindings(_ root: URL, _ defaults: UserDefaults,
                          boundary: FoodJournalWriterBoundary = .legacy) -> FoodJournalRuntimeFactory.Bindings {
        .init(defaults: defaults, goals: NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
            writerBoundary: boundary, mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("migration"),
            repairBackupDirectory: root.appendingPathComponent("repair"), afterRestoreCommit: {})
    }
    func testBindsExactContainerAndDefaultsWithoutMigratingLegacyOrRunningCleanup() throws {
        try fixture { root, defaults, container in
            let legacy = Data("retained unreadable legacy bytes".utf8)
            defaults.set(legacy, forKey: NutritionDiaryRepository.storageKey)
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let row = Ate.JournalEntry(prompt: "", text: "Retained reflection", state: nil)
            let writer = ModelContext(container)
            writer.insert(row)
            try writer.save()
            let runtime = try FoodJournalRuntimeFactory.bind(container: container, openState: .ok,
                                                             bindings: bindings(root, defaults))
            XCTAssertTrue(runtime.journal.container === container)
            XCTAssertTrue(runtime.defaults === defaults)
            XCTAssertTrue(runtime.goalsRepository.defaults === defaults)
            XCTAssertEqual((runtime.goalsRepository.storage as? FileNutritionGoalsStorage)?.fileURL,
                           root.appendingPathComponent("goals.json"))
            XCTAssertEqual(try runtime.readReflections().map(\.text), ["Retained reflection"])
            XCTAssertEqual(runtime.openState, .ok)
            XCTAssertFalse(container.mainContext.autosaveEnabled)
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
            XCTAssertEqual(defaults.data(forKey: NutritionDiaryRepository.storageKey), legacy)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("repair").path))
        }
    }
    func testUnavailableRecoveredFallbackAndInMemoryCannotBecomeReady() throws {
        try fixture { root, defaults, container in
            let bound = bindings(root, defaults)
            for state in [JournalOpenState.recovered(backupName: "existing"), .inMemoryFallback(error: nil), .unavailable(error: nil)] {
                XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: state, bindings: bound))
            }
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: nil, openState: .ok, bindings: bound))
            let memory = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: memory, openState: .ok, bindings: bound)) {
                XCTAssertEqual($0 as? FoodJournalRuntimeFactory.Failure, .nondurable)
            }
        }
    }
    func testPendingChangesAndMismatchedBindingsRefuseWithoutDiscardingWork() throws {
        try fixture { root, defaults, container in
            let pending = Ate.JournalEntry(prompt: "", text: "uncommitted", state: nil)
            container.mainContext.insert(pending)
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: .ok, bindings: bindings(root, defaults))) {
                XCTAssertEqual($0 as? FoodJournalRuntimeFactory.Failure, .pendingChanges)
            }
            XCTAssertTrue(container.mainContext.hasChanges)
            XCTAssertEqual(pending.text, "uncommitted")
            container.mainContext.rollback()
            let other = UserDefaults(suiteName: "Factory-other-\(UUID().uuidString)")!
            let mismatch = FoodJournalRuntimeFactory.Bindings(defaults: defaults, goals: NutritionGoalsRepository(defaults: other),
                writerBoundary: .legacy, mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: root.appendingPathComponent("m"),
                repairBackupDirectory: root.appendingPathComponent("r"), afterRestoreCommit: {})
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: .ok, bindings: mismatch)) {
                XCTAssertEqual($0 as? FoodJournalRuntimeFactory.Failure, .defaultsMismatch)
            }
            let samePath = root.appendingPathComponent("same")
            let invalid = FoodJournalRuntimeFactory.Bindings(defaults: defaults, goals: bindings(root, defaults).goals,
                writerBoundary: .legacy, mediaDirectory: root.appendingPathComponent("media"), migrationBackupDirectory: samePath,
                repairBackupDirectory: samePath, afterRestoreCommit: {})
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: .ok, bindings: invalid))
        }
    }
    func testReadOnlyAndMissingPayloadSchemaCannotBind() throws {
        try fixture { root, defaults, _ in
            let readOnly = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store"), allowsSave: false))
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: readOnly, openState: .ok, bindings: bindings(root, defaults))) {
                XCTAssertEqual($0 as? FoodJournalRuntimeFactory.Failure, .readOnly)
            }
            let partial = try ModelContainer(for: Ate.JournalEntry.self,
                configurations: ModelConfiguration(url: root.appendingPathComponent("partial.store")))
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: partial, openState: .ok, bindings: bindings(root, defaults))) {
                XCTAssertEqual($0 as? FoodJournalRuntimeFactory.Failure, .incompatibleSchema)
            }
        }
    }
    func testUnreadableMealPairingIsNotReadyAndBytesRemainAvailableForRecovery() throws {
        try fixture { root, defaults, container in
            let row = Ate.JournalEntry(prompt: "", text: "orphan", state: nil)
            row.kindRaw = JournalEntryKind.meal.rawValue
            let writer = ModelContext(container)
            writer.insert(row)
            try writer.save()
            let before = defaults.dictionaryRepresentation() as NSDictionary
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: .ok, bindings: bindings(root, defaults)))
            let reader = ModelContext(container)
            XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Ate.JournalEntry>()), 1)
            XCTAssertEqual(try reader.fetchCount(FetchDescriptor<JournalMealPayload>()), 0)
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }
    func testBoundaryRefusalPrecedesBindingAndLaterRefusalCoversCookingHistory() throws {
        try fixture { root, defaults, container in
            var allowed = false
            let boundary = FoodJournalWriterBoundary { effect in
                guard allowed else { throw Denied.owner }; try effect()
            }
            XCTAssertThrowsError(try FoodJournalRuntimeFactory.bind(container: container, openState: .ok,
                                                                   bindings: bindings(root, defaults, boundary: boundary)))
            allowed = true
            let runtime = try FoodJournalRuntimeFactory.bind(container: container, openState: .ok,
                                                             bindings: bindings(root, defaults, boundary: boundary))
            let date = Date()
            try runtime.cookingHistory.recordVerified(recipeID: "kept", date: date, dayKey: runtime.cookingHistory.key(for: date))
            let before = defaults.dictionaryRepresentation() as NSDictionary
            allowed = false
            runtime.cookingHistory.record(recipeID: "denied", date: date)
            runtime.cookingHistory.clear()
            XCTAssertThrowsError(try runtime.cookingHistory.recordVerified(recipeID: "denied", date: date,
                                                                           dayKey: runtime.cookingHistory.key(for: date)))
            XCTAssertThrowsError(try runtime.journal.saveManual(text: "denied"))
            XCTAssertEqual(runtime.cookingHistory.recipeIDs(on: date), ["kept"])
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }
}
