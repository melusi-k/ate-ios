import XCTest
@testable import Ate

final class LibraryChromeClearanceTests: XCTestCase {
    func testMeasuredFloatingBandCanExceedOldNinetySixPointSpacer() {
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 874, chromeTop: 700), 190)
    }
    func testAlreadyInsetViewportDoesNotDoubleReserveChrome() {
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 700, chromeTop: 700), 16)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 680, chromeTop: 700), 16)
    }
    func testChangesInOrientationAndChromeHeightUseNewMeasurement() {
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 402, chromeTop: 300), 118)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 402, chromeTop: 250), 168)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 402, chromeTop: 410), 16)
    }
    func testMissingAndInvalidGeometryRetainsPreMeasurementFallback() {
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: nil, chromeTop: 500), 96)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 800, chromeTop: nil), 96)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: .infinity, chromeTop: 500), 96)
        XCTAssertEqual(LibraryChromeClearance.reserve(hostBottom: 800, chromeTop: .nan), 96)
    }
}
