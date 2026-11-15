import XCTest
@testable import Ate

final class ProductUpdatesTests: XCTestCase {
    func testRealHostBundleContainsReadableCatalogInRequiredDirectory() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json",
                                               subdirectory: "ProductUpdates"))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ProductUpdates")
        let catalog = try XCTUnwrap(ProductUpdatesCatalog.load(), "Load the actual Ate host bundle, not a test fixture")
        XCTAssertFalse(catalog.releases.isEmpty)
        XCTAssertTrue(catalog.releases.contains { $0.id == "product-updates-introduction" })
        XCTAssertFalse(catalog.visibleReleases(build: 445, channel: "beta").isEmpty)
        XCTAssertFalse(catalog.visibleReleases(build: 445, channel: "release").isEmpty)
    }

    func testRealHostBundleListsPublishedBuildsNewestFirstAsSeparateReleases() throws {
        let catalog = try XCTUnwrap(ProductUpdatesCatalog.load())
        let builds = catalog.publishedBuildReleases(build: 445, channel: "beta")
        XCTAssertGreaterThan(builds.count, 1)
        XCTAssertEqual(Array(builds.prefix(5)).map(\.buildNumber), [445, 444, 443, 442, 441])
        XCTAssertEqual(builds.first?.id, "build-445-TierA")
        XCTAssertEqual(builds.first?.title, "Build 445")
        XCTAssertTrue(builds.first?.summary.contains("Bundle A") == true)
        XCTAssertEqual(Set(builds.map(\.id)).count, builds.count)
        XCTAssertFalse(builds.contains { $0.id == "latest-build" || $0.id == "product-updates-introduction" })
        XCTAssertFalse(catalog.publishedBuildReleases(build: 442, channel: "release").contains { ($0.buildNumber ?? 0) > 442 })
    }

    private func data(_ releases: String = "[]", schema: Int = 1) -> Data {
        Data("{\"schemaVersion\":\(schema),\"releases\":\(releases)}".utf8)
    }
    private func release(id: String, build: Int, channel: String = "all", slides: String = "[]") -> String {
        "{\"id\":\"\(id)\",\"title\":\"Update\",\"version\":\"0.1.0\",\"minimumBuild\":\(build),\"channel\":\"\(channel)\",\"summary\":\"Benefit\",\"changes\":[],\"slides\":\(slides)}"
    }
    private let slide = #"{"id":"one","imageAsset":"missing","imageAlt":"Alt","title":"Title","body":"Body","placeholder":true}"#
    func testEmptyAndOneReleaseWithZeroOrOneSlide() throws {
        XCTAssertTrue(try ProductUpdatesCatalog.decode(data()).releases.isEmpty)
        let zero = try ProductUpdatesCatalog.decode(data("[\(release(id: "zero", build: 1))]"))
        XCTAssertTrue(zero.releases[0].slides.isEmpty)
        let one = try ProductUpdatesCatalog.decode(data("[\(release(id: "one", build: 1, slides: "[\(slide)]"))]"))
        XCTAssertEqual(one.releases[0].slides.map(\.id), ["one"])
    }
    func testManyReleaseOrderingChannelAndFutureBuildFiltering() throws {
        let rows = [release(id: "old", build: 1), release(id: "new", build: 3), release(id: "beta", build: 2, channel: "beta"),
                    release(id: "future", build: 9), release(id: "release", build: 2, channel: "release")]
        let catalog = try ProductUpdatesCatalog.decode(data("[" + rows.joined(separator: ",") + "]"))
        XCTAssertEqual(catalog.visibleReleases(build: 3, channel: "release").map(\.id), ["new", "release", "old"])
        XCTAssertEqual(catalog.visibleReleases(build: 3, channel: "beta").map(\.id), ["new", "beta", "old"])
    }
    func testInvalidSchemaDuplicateReleaseChannelBuildAndCopyRefuse() throws {
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data(schema: 2)))
        let valid = release(id: "duplicate", build: 1)
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[\(valid),\(valid)]")))
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[\(release(id: "bad", build: -1))]")))
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[\(release(id: "bad", build: 1, channel: "draft"))]")))
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[" + valid.replacingOccurrences(of: "Benefit", with: "") + "]")))
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(Data("{}".utf8)))
    }
    func testDuplicateSlidesAndMoreThanFiveRefuseButMissingAssetDoesNotDropText() throws {
        let six = "[" + Array(repeating: slide, count: 6).joined(separator: ",") + "]"
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[\(release(id: "bad", build: 1, slides: six))]")))
        XCTAssertThrowsError(try ProductUpdatesCatalog.decode(data("[\(release(id: "bad", build: 1, slides: "[\(slide),\(slide)]"))]")))
        let catalog = try ProductUpdatesCatalog.decode(data("[\(release(id: "kept", build: 1, slides: "[\(slide)]"))]"))
        XCTAssertEqual(catalog.releases[0].slides[0].body, "Body")
        XCTAssertEqual(catalog.releases[0].slides[0].imageAsset, "missing")
    }
}
