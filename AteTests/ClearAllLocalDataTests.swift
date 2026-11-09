import XCTest
import SwiftData
@testable import Ate

@MainActor
final class ClearAllLocalDataTests: XCTestCase {
    enum Injected: Error { case failure }
    func testJournalClearsInvalidFutureRowsAndOrphanPayloads() throws {
        let c = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let row = Ate.JournalEntry(id: "future", prompt: "p", text: "secret", state: .balanced)
        row.kindRaw = "future-kind"; row.stateRaw = "future-state"; ctx.insert(row)
        ctx.insert(JournalMealPayload(entryID: "orphan", meal: .dinner, foodName: "Pap", quantity: 1,
            quantityUnit: "bowl", servings: 1, source: .userProvided, sourceName: "You",
            nutrients: NutritionSnapshot(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil)))
        try ctx.save()
        let component = ClearAllLocalData.journal(container: c, validateWriterGate: {})
        let report = try ClearAllLocalData.execute([component], requiredNames: [component.name], validateWriterGate: {})
        XCTAssertTrue(report.complete)
        XCTAssertTrue(try ModelContext(c).fetch(FetchDescriptor<Ate.JournalEntry>()).isEmpty)
        XCTAssertTrue(try ModelContext(c).fetch(FetchDescriptor<JournalMealPayload>()).isEmpty)
    }
    func testDefaultsOwnedKeysRemovedWithoutTouchingCredentialsOrOtherApps() throws {
        let suite = "ClearAllFixtures-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        for key in ClearAllDataKeys.standard { defaults.set("fixture", forKey: key) }
        defaults.set("fixture", forKey: "insights.lifecycle.v1.account.fixture")
        defaults.set("preserve", forKey: "other-app-key"); defaults.set("preserve", forKey: "ate.sync.v1")
        let component = ClearAllLocalData.defaults(name: "standard", store: defaults, keys: ClearAllDataKeys.standard,
            prefixes: ClearAllDataKeys.standardPrefixes, validateWriterGate: {})
        try component.erase(); try component.verifyEmpty()
        XCTAssertEqual(defaults.string(forKey: "other-app-key"), "preserve")
        XCTAssertEqual(defaults.string(forKey: "ate.sync.v1"), "preserve")
    }
    func testFailureIsPartialAndOtherComponentsStillRun() throws {
        var cleared = false
        let bad = ClearAllLocalData.Component(name: "bad", erase: { throw Injected.failure }, verifyEmpty: {})
        let good = ClearAllLocalData.Component(name: "good", erase: { cleared = true }, verifyEmpty: {})
        let result = try ClearAllLocalData.execute([bad, good], requiredNames: ["bad", "good"], validateWriterGate: {})
        XCTAssertFalse(result.complete); XCTAssertTrue(cleared); XCTAssertEqual(result.failures.first?.component, "bad")
        XCTAssertEqual(result.verifiedEmpty, ["good"])
    }
    func testGateLossStopsErasureAndMissingComponentRefuses() throws {
        var writes = 0
        let c = ClearAllLocalData.Component(name: "one", erase: { writes += 1 }, verifyEmpty: {})
        XCTAssertThrowsError(try ClearAllLocalData.execute([c], requiredNames: ["one", "missing"], validateWriterGate: {}))
        XCTAssertThrowsError(try ClearAllLocalData.execute([c], requiredNames: ["one"], validateWriterGate: { throw Injected.failure }))
        XCTAssertEqual(writes, 0)
    }
    func testOwnedDirectoryIncludesOrphanBytesButNotSymlinkTarget() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let owned = root.appendingPathComponent("owned"); try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        let outside = root.appendingPathComponent("preserve.bin"); try Data([42]).write(to: outside)
        try Data([1,2,3]).write(to: owned.appendingPathComponent("orphan.jpg"))
        try FileManager.default.createSymbolicLink(at: owned.appendingPathComponent("link"), withDestinationURL: outside)
        let component = ClearAllLocalData.directory(name: "media", url: owned, validateWriterGate: {})
        try component.erase(); try component.verifyEmpty()
        XCTAssertEqual(try Data(contentsOf: outside), Data([42]))
    }
    func testJournalSaveFailureNeverClaimsComplete() throws {
        let c = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c); ctx.insert(Ate.JournalEntry(prompt: "p", text: "keep", state: .balanced)); try ctx.save()
        let part = ClearAllLocalData.journal(container: c, validateWriterGate: {}, save: { _ in throw Injected.failure })
        let result = try ClearAllLocalData.execute([part], requiredNames: [part.name], validateWriterGate: {})
        XCTAssertFalse(result.complete)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<Ate.JournalEntry>()).count, 1)
    }
}
