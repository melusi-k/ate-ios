import XCTest
@testable import Ate

final class ProductUpdatesTests: XCTestCase {
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
