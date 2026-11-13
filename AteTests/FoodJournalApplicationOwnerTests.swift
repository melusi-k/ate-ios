import XCTest
@testable import Ate

@MainActor
final class FoodJournalApplicationOwnerTests: XCTestCase {
    func testSessionDecodeDistinguishesAbsenceFromCorruptionAndInvalidIdentity() throws {
        XCTAssertNil(try FoodJournalApplicationOwner.decodeSession(nil))
        XCTAssertThrowsError(try FoodJournalApplicationOwner.decodeSession(Data("bad".utf8)))
        let original = AuthSession(accessToken: "first", refreshToken: "refresh", expiresAt: 4_102_444_800,
            userID: "owner", email: "fixture@example.invalid")
        XCTAssertEqual(try FoodJournalApplicationOwner.decodeSession(JSONEncoder().encode(original)), original)
        var invalid = original; invalid.userID = ""
        XCTAssertThrowsError(try FoodJournalApplicationOwner.decodeSession(JSONEncoder().encode(invalid)))
        invalid = original; invalid.accessToken = ""
        XCTAssertThrowsError(try FoodJournalApplicationOwner.decodeSession(JSONEncoder().encode(invalid)))
    }

    func testControlProvisionRejectsExistingSymlinkAndNonDirectoryWithoutChangingTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RootControl-\(UUID())")
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let sentinel = target.appendingPathComponent("personal")
        try Data("keep".utf8).write(to: sentinel)
        let control = root.appendingPathComponent("control")
        try FileManager.default.createSymbolicLink(at: control, withDestinationURL: target)
        XCTAssertThrowsError(try FoodJournalApplicationOwner.provisionControlDirectory(control))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        try FileManager.default.removeItem(at: control)
        try Data("not a directory".utf8).write(to: control)
        XCTAssertThrowsError(try FoodJournalApplicationOwner.provisionControlDirectory(control))
        try FileManager.default.removeItem(at: control)
        try FoodJournalApplicationOwner.provisionControlDirectory(control)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: control.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testActualAssociationBoundaryRefusesAfterOwnerRevokedWithoutChangingSavedLinks() throws {
        let suite = "AssociationOwner-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        enum Closed: Error { case owner }
        var active = true
        let boundary = FoodJournalWriterBoundary { work in guard active else { throw Closed.owner }; try work() }
        let links = NutritionRecipeAssociationStore(defaults: defaults, writerBoundary: boundary)
        let entry = UUID()
        try links.associate(entryID: entry, recipeID: "recipe", recipeName: "Original")
        let saved = defaults.data(forKey: NutritionRecipeAssociationStore.storageKey)
        active = false
        XCTAssertThrowsError(try links.associate(entryID: entry, recipeID: "replacement", recipeName: "Stale"))
        XCTAssertThrowsError(try links.dissociate(entryID: entry))
        XCTAssertEqual(defaults.data(forKey: NutritionRecipeAssociationStore.storageKey), saved)
    }
    func testShippingOwnerSelectorStaysOffWithoutExplicitDebugQualification() {
        XCTAssertFalse(AppConfig.foodJournalEnabled)
        XCTAssertFalse(AppConfig.foodJournalProductionOwnerSelected(arguments: []))
        XCTAssertFalse(AppConfig.foodJournalProductionOwnerSelected(arguments: ["-UITesting"]))
    }

    func testDebugQualificationCannotSelectHermeticTestingOrReleaseActivation() {
        XCTAssertFalse(AppConfig.foodJournalProductionOwnerSelected(arguments: ["-UITesting", "-qaFoodJournalProductionOwner"]))
        #if DEBUG
        XCTAssertTrue(AppConfig.foodJournalProductionOwnerSelected(arguments: ["-qaFoodJournalProductionOwner"]))
        #else
        XCTAssertFalse(AppConfig.foodJournalProductionOwnerSelected(arguments: ["-qaFoodJournalProductionOwner"]))
        #endif
    }

}
