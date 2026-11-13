import XCTest
@testable import Ate

@MainActor
final class FoodJournalAppGraphTests: XCTestCase {
    private struct Surfaces: ClearAllSystemSurfaceCleaning {
        func cleanupAfterLocalErase() async -> [String] { [] }
    }
    private final class Archive: ArchiveNestedLeaseBoundary {
        var commits = 0
        func withNestedLease<T>(_ work: () throws -> T) throws -> T {
            let value = try work()
            commits += 1
            return value
        }
    }
    private func fixture(_ body: (URL, UserDefaults, AccountResetComposition, Archive) async throws -> Void) async throws {
        let suite = "FoodJournalGraph-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let directory = requested.resolvingSymlinksInPath().standardizedFileURL
        let previous = AppStore.current
        let keys = ["ate.cookSession.v1", "ate.settings.v1", "ate.timerprefs.v1", "ate.sync.v1"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        defer {
            AppStore.current = previous
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
            for key in keys {
                if let value = saved[key] ?? nil { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let rpc = AccountDataResetService(baseURL: try XCTUnwrap(URL(string: "https://fixture.invalid")),
            key: "fixture", perform: { _ in XCTFail("signed-out fixture must not contact server"); throw ResetRPCError.unauthorized })
        let composition = try AccountResetComposition(controlDirectory: directory, rpc: rpc,
            currentSession: { nil }, surfaces: Surfaces(), components: {
                XCTFail("no reset expected"); throw ResetRPCError.invalidRequest("unexpected reset")
            })
        try await body(directory, defaults, composition, Archive())
    }

    private func resources(_ directory: URL, _ defaults: UserDefaults,
                           boundary: FoodJournalWriterBoundary) -> FoodJournalAppGraph.Resources {
        .init(recipeContext: nil, journal: JournalStore(inMemory: true, writerBoundary: boundary),
            defaults: defaults, goals: NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
            migrationBackupDirectory: directory.appendingPathComponent("migration"),
            repairBackupDirectory: directory.appendingPathComponent("repair"),
            afterRestoreCommit: {})
    }

    func testBlockedAdmissionNeverConstructsPersonalResourcesOrConsumers() async throws {
        try await fixture { directory, defaults, composition, archive in
            var constructed = false
            let startup = FoodJournalAppGraph.startup(composition: composition, archive: archive,
                backend: MockBackend(), authorizeLocalState: { _, _ in XCTFail("must not build") },
                authorizeAdmission: { _ in throw JournalStartupAuthorizationError.blocked("account snapshot unverifiable") },
                makeResources: { boundary in constructed = true; return self.resources(directory, defaults, boundary: boundary) },
                makeConsumers: { _ in XCTFail("must not bind"); throw ResetRPCError.unauthorized })
            await startup.start()
            XCTAssertFalse(constructed)
            XCTAssertEqual(archive.commits, 0)
            guard case .blocked(.unavailable("account snapshot unverifiable")) = startup.state else {
                return XCTFail("must preserve admission reason")
            }
        }
    }

    func testReadyGraphRetainsOriginalLeaseAndAllConsumerCapabilities() async throws {
        try await fixture { directory, defaults, composition, archive in
            var order: [String] = []
            var exported = false
            let startup = FoodJournalAppGraph.startup(composition: composition, archive: archive,
                backend: MockBackend(), authorizeLocalState: { _, _ in order.append("local") },
                authorizeAdmission: { _ in order.append("snapshot"); await Task.yield() },
                makeResources: { boundary in order.append("resources"); return self.resources(directory, defaults, boundary: boundary) },
                makeConsumers: { runtime in
                    order.append("consumers")
                    XCTAssertTrue(runtime.defaults === defaults)
                    return .init(exportArchive: { exported = true; return Data("bound export".utf8) },
                        importArchive: { _ in DataImportSummary(recipesAdded: 2) },
                        preservationDirectory: directory.appendingPathComponent("preserved"))
                })
            await startup.start()
            guard case .ready(let graph) = startup.state else { return XCTFail("must admit graph") }
            XCTAssertEqual(order, ["snapshot", "local", "resources", "consumers"])
            XCTAssertTrue(graph.composition === composition)
            XCTAssertTrue(graph.store.foodJournalRuntime === graph.runtime)
            XCTAssertTrue(graph.runtime.writerBoundary === graph.writerBoundary)
            XCTAssertTrue(graph.store.timers.writerBoundary === graph.writerBoundary)
            XCTAssertEqual(graph.store.journalResetPreservationDirectory, directory.appendingPathComponent("preserved"))
            XCTAssertEqual(archive.commits, 1, "nested constructors share one covered unit")
            XCTAssertEqual(try graph.store.importJSON(Data()).recipesAdded, 2)
            let bytes = try await graph.store.exportUserData()
            XCTAssertEqual(bytes, Data("bound export".utf8))
            XCTAssertTrue(exported)
            try composition.gate.validateWriter(graph.writerLease)
        }
    }

    func testAdmittedCookRetryKeepsSessionSnapshotOutboxAndNeverCreatesMeal() async throws {
        try await fixture { directory, defaults, composition, archive in
            let startup = FoodJournalAppGraph.startup(composition: composition, archive: archive,
                backend: MockBackend(), authorizeLocalState: { _, _ in }, authorizeAdmission: { _ in },
                makeResources: { self.resources(directory, defaults, boundary: $0) },
                makeConsumers: { _ in .init(exportArchive: { Data() }, importArchive: { _ in DataImportSummary() },
                    preservationDirectory: directory.appendingPathComponent("preserved")) })
            await startup.start()
            guard case .ready(let graph) = startup.state else { return XCTFail("must admit graph") }
            let recipe = RecipeCard(title: "Retained soup")
            graph.store.add(recipe)
            graph.store.beginCookSession(recipeID: recipe.id, factor: 2)
            graph.store.updateCookSession(recipeID: recipe.id, stepIndex: 2)
            let session = try graph.store.prepareCookCompletion(recipeID: recipe.id)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let event = CookCompletionEvent(recipeID: recipe.id, recipeTitle: recipe.title, completedAt: date,
                dayKey: graph.runtime.cookingHistory.key(for: date), id: "cook-" + session.sessionID)
            try graph.runtime.cookOutbox.enqueue(event)
            try graph.store.recordCompletedCook(event)
            try graph.runtime.cookOutbox.enqueue(event)
            try graph.store.recordCompletedCook(event)
            XCTAssertEqual(try graph.runtime.cookOutbox.load(), [event])
            XCTAssertEqual(graph.store.cookSession?.sessionID, session.sessionID)
            XCTAssertEqual(graph.store.cookSession?.factor, 2)
            XCTAssertEqual(graph.store.cookSession?.stepIndex, 2)
            XCTAssertTrue(try graph.runtime.readMeals().isEmpty, "Finish is not eaten food")
            XCTAssertTrue(try graph.runtime.readReflections().isEmpty, "Finish alone saves no reflection or Health state")
            try composition.gate.invalidateWriters()
            let before = defaults.data(forKey: CookCompletionOutbox.defaultsKey)
            XCTAssertThrowsError(try graph.runtime.cookOutbox.acknowledge(id: event.id))
            XCTAssertThrowsError(try graph.store.clearCompletedCookSession(sessionID: session.sessionID))
            XCTAssertEqual(defaults.data(forKey: CookCompletionOutbox.defaultsKey), before)
            XCTAssertEqual(graph.store.cookSession?.sessionID, session.sessionID)
        }
    }

    func testDeviceLocalAdmissionNeedsNoSnapshotAndBuildsAfterPreservation() async throws {
        try await fixture { directory, defaults, composition, archive in
            var snapshotCalls = 0
            var recovered = false
            let admission = FoodJournalProductionAdmission(composition: composition, archive: archive,
                preservationDirectory: directory.appendingPathComponent("preserved"),
                legacyDiary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
                snapshot: { _ in snapshotCalls += 1; throw ResetRPCError.contractMissing },
                currentSession: { nil }, localIdentity: "local-fixture", recoverArchive: { owner in
                    XCTAssertEqual(owner, "local-fixture")
                    XCTAssertNil(try composition.receipt.read(), "raw recovery precedes adoption stamp")
                    recovered = true
                })
            let startup = admission.startup(backend: MockBackend(),
                makeResources: { boundary in
                    XCTAssertEqual(try composition.receipt.read(), .init(ownerID: "local-fixture", generation: 0))
                    return self.resources(directory, defaults, boundary: boundary)
                }, makeConsumers: { _ in .init(exportArchive: { Data() }, importArchive: { _ in DataImportSummary() },
                    preservationDirectory: directory.appendingPathComponent("preserved")) })
            await startup.start()
            XCTAssertEqual(snapshotCalls, 0)
            XCTAssertTrue(recovered)
            guard case .ready = startup.state else { return XCTFail("local admission must not require backend") }
        }
    }

    func testSignedInMissingContractBlocksGraphWithoutLocalOwnershipFallback() async throws {
        try await fixture { directory, defaults, composition, archive in
            var constructed = false
            let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
                userID: "signed-in-owner", email: "fixture@example.test")
            let admission = FoodJournalProductionAdmission(composition: composition, archive: archive,
                preservationDirectory: directory.appendingPathComponent("preserved"),
                legacyDiary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
                snapshot: { _ in throw ResetRPCError.contractMissing }, currentSession: { session },
                localIdentity: "local-fixture", recoverArchive: { _ in XCTFail("missing contract must not authorize recovery") })
            let startup = admission.startup(backend: MockBackend(),
                makeResources: { boundary in constructed = true; return self.resources(directory, defaults, boundary: boundary) },
                makeConsumers: { _ in XCTFail("must not bind"); throw ResetRPCError.unauthorized })
            await startup.start()
            XCTAssertFalse(constructed)
            XCTAssertNil(try composition.receipt.read())
            XCTAssertEqual(archive.commits, 0)
            guard case .blocked(.unavailable("account snapshot unverifiable")) = startup.state else {
                return XCTFail("signed-in missing contract must remain blocked")
            }
        }
    }

    func testAdmissionProofRefusesSessionOrReceiptChangesBeforeConstructors() async throws {
        try await fixture { directory, defaults, composition, archive in
            var session: AuthSession?
            let admission = FoodJournalProductionAdmission(composition: composition, archive: archive,
                preservationDirectory: directory.appendingPathComponent("preserved"),
                legacyDiary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
                snapshot: { _ in throw ResetRPCError.contractMissing }, currentSession: { session },
                localIdentity: "local-fixture", recoverArchive: { _ in })
            let lease = try composition.gate.captureWriter()
            try await admission.reconcile(lease: lease)
            try admission.validate(lease: lease, composition: composition)
            session = AuthSession(accessToken: "new", refreshToken: "new", expiresAt: 4_000_000_000,
                userID: "new-owner", email: "fixture@example.test")
            XCTAssertThrowsError(try admission.validate(lease: lease, composition: composition))
            session = nil
            try composition.gate.withWriterEffect(lease) {
                try composition.receipt.save(.init(ownerID: "local-fixture", generation: 1))
            }
            XCTAssertThrowsError(try admission.validate(lease: lease, composition: composition))
        }
    }


    func testBoundSettingsAndImportedLibraryReloadUseActualRuntimeDomain() async throws {
        try await fixture { directory, defaults, composition, archive in
            var loadedSettings = AppSettings()
            loadedSettings.units = .imperial
            defaults.set(try JSONEncoder().encode(loadedSettings), forKey: "ate.settings.v1")
            let startup = FoodJournalAppGraph.startup(composition: composition, archive: archive,
                backend: MockBackend(), authorizeLocalState: { _, _ in }, authorizeAdmission: { _ in },
                makeResources: { self.resources(directory, defaults, boundary: $0) },
                makeConsumers: { _ in .init(exportArchive: { Data() }, importArchive: { _ in
                    var imported = AppSettings()
                    imported.units = .metric
                    defaults.set(try JSONEncoder().encode(imported), forKey: "ate.settings.v1")
                    return DataImportSummary(journalEntriesAdded: 1)
                }, preservationDirectory: directory.appendingPathComponent("preserved")) })
            await startup.start()
            guard case .ready(let graph) = startup.state else { return XCTFail("must admit graph") }
            XCTAssertEqual(graph.store.settings.units, .imperial)
            graph.store.settings.units = .metric
            let saved = try XCTUnwrap(defaults.data(forKey: "ate.settings.v1"))
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: saved).units, .metric)
            graph.store.settings.units = .imperial
            let summary = try graph.store.importJSON(Data())
            XCTAssertEqual(graph.store.settings.units, .metric, "import must reload the bound settings, not unrelated standard defaults")
            XCTAssertEqual(summary.journalEntriesAdded, 1)
            XCTAssertEqual(summary.message, "Imported 1 Journal entry")
        }
    }


    func testRemoteResetPreflightRefusesRawRecoveryBeforeAnyAdoptionWrite() async throws {
        try await fixture { directory, defaults, composition, archive in
            let session = AuthSession(accessToken: "fixture", refreshToken: "fixture", expiresAt: 4_000_000_000,
                userID: "owner-a", email: "fixture@example.test")
            let lease = try composition.gate.captureWriter()
            try composition.gate.withWriterEffect(lease) {
                try composition.receipt.save(.init(ownerID: session.userID, generation: 0))
            }
            var snapshots = 0
            var recovered = false
            let admission = FoodJournalProductionAdmission(composition: composition, archive: archive,
                preservationDirectory: directory.appendingPathComponent("preserved"),
                legacyDiary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
                snapshot: { _ in snapshots += 1; return AccountSnapshot(generation: 1, rows: []) },
                currentSession: { session }, localIdentity: "local-fixture",
                recoverArchive: { _ in recovered = true })
            do { try await admission.reconcile(lease: lease); XCTFail("remote reset must block") }
            catch JournalStartupAuthorizationError.blocked(let reason) {
                XCTAssertEqual(reason, "remote reset committed; confirmed local erase required")
            }
            XCTAssertEqual(snapshots, 1)
            XCTAssertFalse(recovered)
            XCTAssertEqual(archive.commits, 0)
            XCTAssertEqual(try composition.receipt.read(), .init(ownerID: session.userID, generation: 0))
        }
    }


    func testRawRecoveryFailurePrecedesReceiptStampAndOrdinaryConstructors() async throws {
        try await fixture { directory, defaults, composition, archive in
            let admission = FoodJournalProductionAdmission(composition: composition, archive: archive,
                preservationDirectory: directory.appendingPathComponent("preserved"),
                legacyDiary: NutritionDiaryRepository(defaults: defaults),
                goals: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: directory.appendingPathComponent("goals.json"))),
                snapshot: { _ in XCTFail("local startup must not call snapshot"); throw ResetRPCError.contractMissing },
                currentSession: { nil }, localIdentity: "local-fixture",
                recoverArchive: { _ in throw ArchiveNestedLeaseFailure.unresolvedRecoveryTransaction })
            let startup = admission.startup(backend: MockBackend(),
                makeResources: { _ in XCTFail("recovery must finish first"); throw ResetRPCError.unauthorized },
                makeConsumers: { _ in XCTFail("recovery must finish first"); throw ResetRPCError.unauthorized })
            await startup.start()
            XCTAssertNil(try composition.receipt.read())
            XCTAssertEqual(archive.commits, 0)
            guard case .failed = startup.state else { return XCTFail("unverified raw recovery must block") }
        }
    }

}
