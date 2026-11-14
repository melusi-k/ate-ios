import XCTest
@testable import Ate
#if DEBUG
final class ExploreRetentionQAFixtureTests: XCTestCase {
    func testFixtureRequiresUITestingAndExplicitSavedFlag() {
        XCTAssertNil(ExploreRetentionQAFixtures.mode(isUITesting: false, arguments: ["-qaExploreRetentionSaved", "-qaExploreRetentionFavourites"]))
        XCTAssertNil(ExploreRetentionQAFixtures.mode(isUITesting: true, arguments: []))
        XCTAssertNil(ExploreRetentionQAFixtures.mode(isUITesting: true, arguments: ["-qaExploreRetentionFavourites"]))
        XCTAssertEqual(ExploreRetentionQAFixtures.mode(isUITesting: true, arguments: ["-qaExploreRetentionSaved"]), .saved)
        XCTAssertEqual(ExploreRetentionQAFixtures.mode(isUITesting: true, arguments: ["-qaExploreRetentionSaved", "-qaExploreRetentionFavourites"]), .favourites)
    }
}
#endif
