import XCTest
@testable import Ate

#if DEBUG
final class ProductReleaseNotesQAFixtureTests: XCTestCase {
    func testOnlyExplicitUITestPinsReleaseHistoryBuild() {
        XCTAssertEqual(ProductReleaseNotesQAFixture.buildNumber(actual: 1, isUITesting: false, arguments: []), 1)
        XCTAssertEqual(ProductReleaseNotesQAFixture.buildNumber(actual: 1, isUITesting: false, arguments: ["-qaReleaseHistory445"]), 1)
        XCTAssertEqual(ProductReleaseNotesQAFixture.buildNumber(actual: 1, isUITesting: true, arguments: []), 1)
        XCTAssertEqual(ProductReleaseNotesQAFixture.buildNumber(actual: 1, isUITesting: true, arguments: ["-qaReleaseHistory445"]), 445)
    }
    func testRealCatalogAtFixtureBuildHasPaginationAndSeparate445444Details() throws {
        let catalog = try XCTUnwrap(ProductUpdatesCatalog.load())
        let build = ProductReleaseNotesQAFixture.buildNumber(actual: 1, isUITesting: true, arguments: ["-qaReleaseHistory445"])
        let releases = catalog.publishedBuildReleases(build: build, channel: "beta")
        XCTAssertGreaterThan(releases.count, 10)
        XCTAssertEqual(Array(releases.prefix(2)).map(\.id), ["build-445-TierA", "build-444-TierA"])
        XCTAssertFalse(releases.prefix(10).contains { $0.id == "build-435-TierA" })
        XCTAssertTrue(releases.prefix(20).contains { $0.id == "build-435-TierA" })
        XCTAssertFalse(catalog.publishedBuildReleases(build: 1, channel: "beta").contains { $0.buildNumber != nil })
    }
}
#endif
