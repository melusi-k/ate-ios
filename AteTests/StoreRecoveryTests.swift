import XCTest
import SwiftData
@testable import Ate

/// R-DATA-01/02: corrupt store fixture + injected save failure.
@MainActor
final class StoreRecoveryTests: XCTestCase {
    private var dir: URL!
    override func setUp() throws {
        try super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ate-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() {
        StoreSaver.resetForTests()
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    func testCorruptStoreIsMovedAsideAndAFreshStoreOpens() throws {
        let url = dir.appendingPathComponent("default.store")
        try Data(repeating: 0x5A, count: 4096).write(to: url)               // corrupt fixture: not SQLite
        try Data("junk".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        let out = StoreRecovery.open(url: url, now: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertNotNil(out.container, "never crashes, always gets a store")
        XCTAssertTrue(out.recovered)
        XCTAssertNotNil(out.error)
        let backup = try XCTUnwrap(out.backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("ate-2025"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path + "-wal"))
        // The fresh store works.
        let ctx = ModelContext(out.container!)
        ctx.insert(RecipeEntity(id: "a", createdAt: 1, position: 0, json: Data("{}".utf8)))
        XCTAssertNoThrow(try ctx.save())
    }

    func testHealthyStoreOpensWithoutRecovery() {
        let out = StoreRecovery.open(url: dir.appendingPathComponent("ok.store"))
        XCTAssertNotNil(out.container); XCTAssertFalse(out.recovered); XCTAssertNil(out.backupURL)
    }

    func testFallsBackToInMemoryWhenEvenAFreshStoreFails() {
        struct Boom: Error {}
        var calls = 0
        let out = StoreRecovery.open(url: dir.appendingPathComponent("x.store")) { cfg in
            calls += 1
            if !cfg.isStoredInMemoryOnly { throw Boom() }
            return try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: cfg)
        }
        XCTAssertTrue(out.inMemoryFallback); XCTAssertNotNil(out.container); XCTAssertEqual(calls, 3)
    }

    func testExportRecoveredWritesJSON() throws {
        let url = try XCTUnwrap(StoreRecovery.exportRecovered([RecipeCard(id: "r1", title: "Mogodu")], dir: dir))
        let back = try JSONDecoder().decode([RecipeCard].self, from: Data(contentsOf: url))
        XCTAssertEqual(back.map(\.id), ["r1"])
    }

    func testInjectedSaveFailureRetriesLogsAndReports() throws {
        struct DiskFull: Error {}
        let c = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var attempts = 0, reported: String?
        StoreSaver.injectFailure = { attempts += 1; throw DiskFull() }
        StoreSaver.onFailure = { reported = $0 }
        XCTAssertFalse(StoreSaver.save(c.mainContext, what: "recipes"))
        XCTAssertEqual(attempts, 3, "1 try + 2 retries")
        XCTAssertEqual(StoreSaver.failures, 1)
        XCTAssertTrue(reported?.contains("Couldn't save your recipes") == true)
        // Recovers once the failure clears.
        StoreSaver.injectFailure = nil
        XCTAssertTrue(StoreSaver.save(c.mainContext, what: "recipes"))
    }

    func testAppStoreSurvivesSaveFailureWithBanner() throws {
        let c = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let s = AppStore(context: c.mainContext, backend: MockBackend())
        var banner: String?
        StoreSaver.injectFailure = { throw NSError(domain: "test", code: 1) }
        StoreSaver.onFailure = { banner = $0 }
        s.add(RecipeCard(id: "x", title: "Pap"))
        XCTAssertEqual(s.recipes.first?.id, "x", "in-memory state kept, no crash")
        XCTAssertNotNil(banner)
    }
}
