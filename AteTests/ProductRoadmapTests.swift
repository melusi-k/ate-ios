import XCTest
@testable import Ate

final class ProductRoadmapTests: XCTestCase {
    private func data(_ features: String = "[]", schema: Int = 1) -> Data {
        Data("{\"schemaVersion\":\(schema),\"features\":\(features)}".utf8)
    }
    private func feature(_ id: String = "one", status: String = "considering", title: String = "Benefit") -> String {
        "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"benefit\":\"User readable copy\",\"status\":\"\(status)\"}"
    }
    func testEmptyCatalogAndAllStatusesRoundTripInReviewedOrder() throws {
        XCTAssertTrue(try ProductRoadmapCatalog.decode(data()).features.isEmpty)
        let rows = ProductRoadmapFeature.Status.allCases.enumerated().map { feature("feature-\($0.offset)", status: $0.element.rawValue) }
        let catalog = try ProductRoadmapCatalog.decode(data("[" + rows.joined(separator: ",") + "]"))
        let decoded = try ProductRoadmapCatalog.decode(JSONEncoder().encode(catalog))
        XCTAssertEqual(decoded.features.map(\.id), ["feature-0", "feature-1", "feature-2", "feature-3"])
        XCTAssertEqual(decoded.features.map(\.status), ProductRoadmapFeature.Status.allCases)
    }
    func testInvalidSchemaUnknownStatusDuplicateIdentityAndBlankCopyRefuse() throws {
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(data(schema: 2)))
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(data("[\(feature(status: "soon"))]")))
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(data("[\(feature()),\(feature())]")))
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(data("[\(feature(title: "   "))]")))
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(data("[\(feature("../unsafe"))]")))
        XCTAssertThrowsError(try ProductRoadmapCatalog.decode(Data("{}".utf8)))
    }
    func testVotingRemainsUnavailableWithoutClaimingAcceptedOrQueuedVotes() {
        XCTAssertFalse(ProductRoadmapVoting.available)
        XCTAssertTrue(ProductRoadmapVoting.explanation.contains("No vote has been sent or saved"))
        XCTAssertTrue(ProductRoadmapVoting.limits.contains("not per person"))
        XCTAssertTrue(ProductRoadmapVoting.limits.contains("Reinstalling"))
    }
}
