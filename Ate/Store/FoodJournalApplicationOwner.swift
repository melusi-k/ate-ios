import Foundation
import Observation
import SwiftData
import Darwin

/// The one application root owns admission and replacement. No AppStore or
/// ordinary timer is created until reset resume and account snapshot proof finish.
@Observable
@MainActor
final class FoodJournalApplicationOwner {
    enum State {
        case checking
        case blocked(String)
        case ready(UUID, AppStore)
    }
    enum Failure: Error { case unavailable, identityChanged, resetUnverified, keychainUnverified }
    private(set) var state: State = .checking
    private var session: AuthSession?
    private var graph: FoodJournalProductionGraph?
    private var store: AppStore?
    private var resources: FoodJournalDiskResources?
    private var gate: AccountWriterGate?
    private var control: FileResetControlPersistence?
    private var receipts: AccountGenerationReceiptStore?
    private var rpc: AccountDataResetService?
    private var transitions: FoodJournalGraphTransitions?
    private var paths: FoodJournalResetInventory.Paths?
    private var recipeURL: URL?
    private var journalURL: URL?
    private var started = false
    private var mountedID: UUID?
    private var retirementWaiter: CheckedContinuation<Void, Never>?
    private var pendingPasswordRecovery = false
    private var pendingURL: URL?
    private let localIdentity = "ate-local-installation"

    func start() async {
        guard !started else { return }
        started = true
        do {
            guard SharedWriterBoundary.install(.requiresCapturedOwner) else { throw Failure.unavailable }
            let fm = FileManager.default
            let shared = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedContainer.groupID)
            let directory: URL
            if let shared {
                directory = shared.resolvingSymlinksInPath().appendingPathComponent(SharedWriterControl.directoryName, isDirectory: true)
                try Self.provisionControlDirectory(directory)
            } else {
                // Explicit app-only mode: no extension is represented as shared.
                directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
                    .appendingPathComponent(SharedWriterControl.directoryName, isDirectory: true)
                try Self.provisionControlDirectory(directory)
            }
            var metadata = stat()
            guard lstat(directory.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
            let controlDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
            let control = FileResetControlPersistence(directory: controlDirectory)
            self.control = control
            self.gate = try AccountWriterGate(directory: controlDirectory, resetControlExists: { try control.read() != nil })
            self.receipts = try AccountGenerationReceiptStore(directory: controlDirectory)
            session = try Self.decodeSession(try Keychain.loadVerified(account: "session"))
            guard let url = AppConfig.supabaseURL, !AppConfig.supabasePublishableKey.isEmpty else { throw Failure.unavailable }
            rpc = AccountDataResetService(baseURL: url, key: AppConfig.supabasePublishableKey)
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sharedFiles = shared ?? support
            recipeURL = StoreRecovery.defaultStoreURL.standardizedFileURL
            journalURL = ModelConfiguration("AteJournal").url.standardizedFileURL
            paths = .init(media: JournalStore.mediaDir.standardizedFileURL,
                legacyDiaryBackups: JournalLocalReset.defaultMigrationBackupDirectory.standardizedFileURL,
                repairDiaryBackups: JournalLocalReset.defaultRepairBackupDirectory.standardizedFileURL,
                adoptionPreservation: support.appendingPathComponent("FoodJournalPreservation", isDirectory: true).standardizedFileURL,
                covers: sharedFiles.appendingPathComponent("Covers", isDirectory: true).standardizedFileURL,
                inboxMedia: sharedFiles.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL,
                recipeBackups: StoreRecovery.defaultStoreURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true).standardizedFileURL,
                recoveredExports: documents.standardizedFileURL,
                goalsDirectory: FileNutritionGoalsStorage().fileURL.deletingLastPathComponent().standardizedFileURL,
                control: controlDirectory)
            try await refreshStartupSessionIfNeeded()
            try await resumeLocalActionIfPending(unopened: true)
            if let outcome = await resetCoordinator(unopened: true).resumeIfPending(), outcome != .completed {
                throw Failure.resetUnverified
            }
            try await rebuild()
        } catch { block() }
    }

    private func refreshStartupSessionIfNeeded() async throws {
        guard let original = session, original.expiresAt < Date().timeIntervalSince1970 + 60,
              let gate, let control, let receipts, let rpc else { return }
        if let bytes = try control.read(),
           let record = try? JSONDecoder().decode(LocalActionRecord.self, from: bytes),
           record.format == "ate-local-account-action-v1" { return }
        let originalBytes = try Keychain.loadVerified(account: "session")
        guard try Self.decodeSession(originalBytes) == original else { throw Failure.identityChanged }
        // Snapshot minimal control under the short gate. No ordinary owner exists
        // yet, and no flock is held while the auth network request runs.
        try gate.acquireResetGate()
        let originalControl: Data?, originalReceipt: AccountGenerationPolicy.Receipt?
        do {
            originalControl = try control.read(); originalReceipt = try receipts.read()
            try gate.validateResetGate(); gate.releaseResetGate()
        } catch { gate.releaseResetGate(); throw error }
        let replacement = try await SupabaseAuth(baseURL: rpc.baseURL, key: rpc.key).refresh(original)
        guard replacement.userID == original.userID else { throw Failure.identityChanged }
        try gate.acquireResetGate(); defer { gate.releaseResetGate() }
        guard session == original, try Keychain.loadVerified(account: "session") == originalBytes,
              try control.read() == originalControl, try receipts.read() == originalReceipt else { throw Failure.identityChanged }
        try persistSession(replacement)
        try gate.validateResetGate()
    }

    static func decodeSession(_ bytes: Data?) throws -> AuthSession? {
        guard let bytes else { return nil }
        let session = try JSONDecoder().decode(AuthSession.self, from: bytes)
        guard !session.userID.isEmpty, !session.accessToken.isEmpty, !session.refreshToken.isEmpty,
              session.expiresAt.isFinite else { throw Failure.identityChanged }
        return session
    }

    static func provisionControlDirectory(_ directory: URL) throws {
        // Never normalize a pre-existing symlink into a trusted control location.
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for part in directory.path.split(separator: "/") {
            cursor.appendPathComponent(String(part), isDirectory: true)
            var info = stat()
            if lstat(cursor.path, &info) != 0 {
                guard errno == ENOENT else { throw Failure.unavailable }
                try fm.createDirectory(at: cursor, withIntermediateDirectories: false)
                guard lstat(cursor.path, &info) == 0 else { throw Failure.unavailable }
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
        }
    }

    private func block() {
        state = .blocked("Ate could not verify saved data, account generation or pending cleanup. Your data stays closed. Reopen Ate after the account-data service is ready.")
    }
    func mounted(_ id: UUID) { mountedID = id }
    func unmounted(_ id: UUID) {
        guard mountedID == id else { return }
        mountedID = nil
        retirementWaiter?.resume(); retirementWaiter = nil
    }
    private func retireEditors() async {
        // Removal of the complete ordinary root dismisses all editor presentations.
        // Await its real onDisappear before revocation/drain and replacement.
        let wasMounted = mountedID != nil
        state = .checking
        if wasMounted { await withCheckedContinuation { retirementWaiter = $0 } }
        AppStore.current = nil
    }

    private func rawInventory(unopened: Bool) throws -> FoodJournalResetInventory {
        guard let paths, let recipeURL, let journalURL else { throw Failure.unavailable }
        let stores: FoodJournalResetInventory.Stores
        if unopened { stores = .unopened(recipeURL: recipeURL, journalURL: journalURL) }
        else {
            guard let graph,
                  let journal = graph.runtime.journal.container else { throw Failure.unavailable }
            // Containers are retained by this exact admitted owner. This access is
            // saved before quiescence; never reopen them under a fresh ordinary lease.
            guard let recipes = retainedRecipes else { throw Failure.unavailable }
            stores = .retained(recipes: recipes, journal: journal)
        }
        return FoodJournalResetInventory(stores: stores, defaults: .standard,
            sharedDefaults: SharedContainer.defaults, goals: FileNutritionGoalsStorage(), paths: paths)
    }
    private var retainedRecipes: ModelContainer?

    private func resetCoordinator(unopened: Bool) -> ClearAllResetCoordinator {
        // Only called after start's concrete dependencies have been assigned.
        let gate = self.gate!, control = self.control!, receipts = self.receipts!, rpc = self.rpc!
        let resetBoundary = FoodJournalWriterBoundary(captureSharedWrites: true) { work in
            try gate.validateResetGate(); try work(); try gate.validateResetGate()
        }
        return ClearAllResetCoordinator(rpc: rpc, gate: gate, surfaces: RootResetSurfaces(
            boundary: resetBoundary, gate: gate), controlPersistence: control,
            currentSession: { self.session }, receiptSink: { generation in
                try gate.validateResetGate()
                guard let session = self.session else { throw Failure.identityChanged }
                try receipts.save(.init(ownerID: session.userID, generation: generation))
            }, components: {
                let inventory = try self.rawInventory(unopened: unopened)
                return try inventory.components(validate: gate.validateResetGate)
            })
    }

    private func rebuild() async throws {
        guard let gate, let control, let receipts, let rpc, let paths, let recipeURL, let journalURL else { throw Failure.unavailable }
        let lease = try gate.captureWriter()
        let archive = ArchiveNestedGenerationBoundary(directory: paths.control)
        let resources = try FoodJournalDiskResources(defaults: .standard, goalsStorage: FileNutritionGoalsStorage(),
            locations: .init(storeFileURL: journalURL, mediaDirectory: paths.media,
                migrationBackupDirectory: paths.legacyDiaryBackups, repairBackupDirectory: paths.repairDiaryBackups,
                preservationDirectory: paths.adoptionPreservation),
            recipeConfiguration: ModelConfiguration(url: recipeURL), journalConfiguration: ModelConfiguration(url: journalURL))
        let admission = try FoodJournalProductionAdmission(gate: gate, control: control, receipts: receipts,
            resources: resources, archive: archive, localIdentity: localIdentity, currentSession: { self.session }, snapshot: rpc.snapshot)
        try await admission.reconcile(admittedLease: lease)
        let graph = try admission.buildGraph(admittedLease: lease, afterRestoreCommit: {})
        let recipes = try resources.recipeContainer(gate: gate, admittedLease: lease)
        let boundary = graph.runtime.writerBoundary
        let tasks = FoodJournalConsumerTasks(lifecycle: graph.lifecycle, sharedBoundary: boundary.sharedBoundary)
        let fenced = GenerationFencedSync(rpc: rpc, currentSession: { self.session },
            captureWriter: { try graph.validate(); return lease }, validateWriter: { candidate in
                guard candidate == lease else { throw Failure.identityChanged }; try graph.validate()
            })
        let sync = FoodJournalGenerationSync(fenced: fenced, receipts: receipts, currentSession: { self.session }, validate: graph.validate)
        // Per-store covers prevent old editors from calling a newly rebound singleton.
        let covers = CoverStore()
        covers.writerBoundary = boundary; covers.validateWriter = graph.validate; covers.consumerTasks = tasks
        // Install actual service boundaries before AppStore.load can publish.
        bindServices(boundary: boundary, graph: graph, tasks: tasks)
        let timers = TimerCenter(writerBoundary: boundary, validateOwner: graph.validate)
        let draft = DraftStore(defaults: .standard, enabled: true, writerBoundary: boundary)
        let insights = InsightsModel()
        insights.validateOwner = graph.validate
        let store = try boundary.withEffect {
            AppStore(context: recipes.mainContext, foodJournalRuntime: graph.runtime, draftStore: draft, timers: timers, coverStore: covers, insightsModel: insights,
                journalWriterEffect: { try boundary.withEffect($0) }, journalWriterValidator: graph.validate,
                injectedAuth: SupabaseAuth(baseURL: rpc.baseURL, key: rpc.key), injectedSync: sync)
        }
        insights.owner = store
        guard store.session == session else { throw Failure.identityChanged }
        self.resources = resources; self.graph = graph; self.store = store; retainedRecipes = recipes
        let transitions = FoodJournalGraphTransitions(graph: graph, retireEditors: { await self.retireEditors() }, rebuild: {
            do { try await self.rebuild() } catch { self.block(); throw error }
        })
        self.transitions = transitions
        store.journalConsumerTasks = tasks
        try graph.lifecycle.register(cancel: { timers.notificationQueue.closeOwner() },
            drain: { await timers.notificationQueue.drainOwner() })
        try graph.lifecycle.register(cancel: { store.cookPlanNotifications.closeOwner() },
            drain: { await store.cookPlanNotifications.drainOwner() })
        DiagnosticHistory.shared.record(SharedContainer.isAvailable ? .sharedContainerMode : .appOnlyContainerMode)
        store.journalArchiveExport = { try await graph.archiveExport.export() }
        store.journalSessionTransition = { next in
            do {
                try await transitions.changeSession { try self.persistSession(next) }
            } catch { self.block(); throw error }
        }
        store.journalRecoverySessionTransition = { next in
            self.pendingPasswordRecovery = true
            do { try await transitions.changeSession { try self.persistSession(next) } }
            catch { self.block(); throw error }
        }
        store.journalArchiveImportAsync = { bytes in
            do { _ = try await transitions.importArchive(bytes) }
            catch {
                if graph.lifecycle.state != .active { self.block() }
                throw error
            }
        }
        store.journalClearAllAsync = {
            do {
                try await transitions.reset {
                    guard await self.resetCoordinator(unopened: false).start() == .completed else { throw Failure.resetUnverified }
                }
            } catch { self.block(); throw error }
        }
        store.journalSignOutRemovingDataAsync = {
            do {
                try await transitions.reset { try await self.localAction(deleteAccount: false, unopened: false) }
            } catch { self.block(); throw error }
        }
        store.journalDeleteAccountAsync = {
            do {
                try await transitions.reset { try await self.localAction(deleteAccount: true, unopened: false) }
            } catch { self.block(); throw error }
        }
        store.journalLocalResetInventory = graph.resetInventory
        store.journalResetPreservationDirectory = paths.adoptionPreservation
        if pendingPasswordRecovery { store.authSheet = .newPassword; pendingPasswordRecovery = false }
        try graph.validate()
        let id = UUID()
        state = .ready(id, store)
        PhoneWatchBridge.shared.activate()
        PhoneWatchBridge.shared.update(session: session)
        if !AppConfig.isUITesting { try tasks.launch { await CoverStore.checkPlayground() } }
        if let launch = AppConfig.launchURL { handle(launch) }
        if let pendingURL { self.pendingURL = nil; handle(pendingURL) }
    }

    private func bindServices(boundary: FoodJournalWriterBoundary, graph: FoodJournalProductionGraph, tasks: FoodJournalConsumerTasks) {
        CoverStore.shared.writerBoundary = boundary
        CoverStore.shared.validateWriter = graph.validate
        CoverStore.shared.consumerTasks = tasks
        PhoneWatchBridge.shared.writerBoundary = boundary
        LiveActivityLog.shared.writerBoundary = boundary
        LiveActivities.validateWriter = graph.validate
        LiveActivities.consumerTasks = tasks
        WidgetBridge.validateWriter = graph.validate
        WidgetBridge.consumerTasks = tasks
    }
    private struct LocalActionRecord: Codable, Equatable {
        let format: String
        let ownerID: String
        var phase: String
    }
    private func saveLocal(_ record: LocalActionRecord) throws {
        guard let gate, let control else { throw Failure.unavailable }
        try gate.validateResetGate()
        let bytes = try JSONEncoder().encode(record)
        try control.write(bytes)
        guard try control.read() == bytes else { throw Failure.resetUnverified }
    }
    private func resumeLocalActionIfPending(unopened: Bool) async throws {
        guard let control, let bytes = try control.read(),
              let record = try? JSONDecoder().decode(LocalActionRecord.self, from: bytes),
              record.format == "ate-local-account-action-v1" else { return }
        guard let gate else { throw Failure.unavailable }
        // A lost delete response cannot be classified as success or safely retried.
        // Keep evidence and block; never erase locally or replay the remote deletion.
        guard record.phase == "localErase" else { throw Failure.resetUnverified }
        try gate.acquireResetGate(); defer { gate.releaseResetGate() }
        guard try control.read() == bytes else { throw Failure.resetUnverified }
        try await completeLocalAction(record, unopened: unopened)
    }
    private func localAction(deleteAccount: Bool, unopened: Bool) async throws {
        guard let gate, let control, let receipts, let rpc else { throw Failure.unavailable }
        guard try control.read() == nil else { throw Failure.resetUnverified }
        let ownerID: String
        if let session { ownerID = session.userID }
        else { ownerID = try receipts.read()?.ownerID ?? localIdentity }
        var record = LocalActionRecord(format: "ate-local-account-action-v1", ownerID: ownerID,
            phase: deleteAccount ? "deleteRequested" : "localErase")
        try gate.acquireResetGate(); defer { gate.releaseResetGate() }
        guard try control.read() == nil else { throw Failure.resetUnverified }
        try saveLocal(record)
        if deleteAccount {
            guard let session, session.userID == ownerID else { throw Failure.identityChanged }
            try await SupabaseAuth(baseURL: rpc.baseURL, key: rpc.key).deleteAccount(session)
            try gate.validateResetGate()
            guard self.session == session else { throw Failure.identityChanged }
            record.phase = "localErase"
            try saveLocal(record)
        }
        try await completeLocalAction(record, unopened: unopened)
    }
    private func completeLocalAction(_ record: LocalActionRecord, unopened: Bool) async throws {
        guard let gate, let control, let receipts else { throw Failure.unavailable }
        try gate.validateResetGate()
        guard record.phase == "localErase", !record.ownerID.isEmpty,
              session == nil || session?.userID == record.ownerID else { throw Failure.identityChanged }
        let inventory = try rawInventory(unopened: unopened)
        let (components, required) = try inventory.components(validate: gate.validateResetGate)
        let report = try ClearAllLocalData.execute(components, requiredNames: required, validateWriterGate: gate.validateResetGate)
        guard report.complete else { throw Failure.resetUnverified }
        let resetBoundary = FoodJournalWriterBoundary(captureSharedWrites: true) { work in
            try gate.validateResetGate(); try work(); try gate.validateResetGate()
        }
        let surfaces = RootResetSurfaces(boundary: resetBoundary, gate: gate)
        guard await surfaces.cleanupAfterLocalErase().isEmpty else { throw Failure.resetUnverified }
        try gate.validateResetGate()
        try persistSession(nil)
        try receipts.save(.init(ownerID: localIdentity, generation: 0))
        try control.remove()
        guard try control.read() == nil else { throw Failure.resetUnverified }
    }

    private func persistSession(_ next: AuthSession?) throws {
        let bytes = try next.map { try JSONEncoder().encode($0) }
        Keychain.save(bytes, account: "session")
        guard try Keychain.loadVerified(account: "session") == bytes else { throw Failure.keychainUnverified }
        session = next
    }
    func handle(_ url: URL) {
        guard case .ready(_, let store) = state else { pendingURL = url; return }
        store.handle(url: url)
    }
}

/// Runs only with the coordinator's real reset gate. Shared callbacks inside the
/// cleanup inherit this reset context, never an ordinary or replacement owner.
@MainActor
private final class RootResetSurfaces: ClearAllSystemSurfaceCleaning {
    let boundary: FoodJournalWriterBoundary
    let gate: AccountWriterGate
    init(boundary: FoodJournalWriterBoundary, gate: AccountWriterGate) {
        self.boundary = boundary; self.gate = gate
    }
    func cleanupAfterLocalErase() async -> [String] {
        // Lazy system dependencies only after local erase: startup resume must
        // not instantiate personal log/bridge singletons during its preflight.
        let base = SystemSurfaceCleanup(timers: nil, validateWriter: gate.validateResetGate)
        DiagnosticHistory.shared.clear()
        BetaQA.shared.clearPersonalCacheAfterReset()
        PhoneWatchBridge.shared.writerBoundary = boundary
        LiveActivityLog.shared.writerBoundary = boundary
        return await SharedWriterBoundary.withCapturedOwner(boundary.sharedBoundary, operation: {
            await base.cleanupAfterLocalErase()
        })
    }
}
