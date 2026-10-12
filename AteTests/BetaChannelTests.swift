import XCTest
@testable import Ate

final class BetaChannelTests: XCTestCase {
    func testOnlyExplicitNonProductionChannelsEnableBetaTools() {
        for channel in ["TierA", "TierB", "TierC", "Beta", "QA", "Internal", "Development"] {
            XCTAssertTrue(AppConfig.isBetaChannel(channel), "\(channel) should enable beta diagnostics")
        }
        for channel in ["", "Production", "production", "AppStore", "Unknown", " TierA "] {
            XCTAssertFalse(AppConfig.isBetaChannel(channel), "\(channel) must not enable beta diagnostics")
        }
    }
}
