import XCTest
@testable import Ate

final class AppGroupResolverTests: XCTestCase {
    func testProfileGroupWinsWhenUsable() {
        let r = AppGroupResolver.resolve(profile: ["group.com.melusik.ate.4B39BSU9DQ"], alt: [], derived: "group.com.melusik.ate.4B39BSU9DQ") { $0.hasSuffix("4B39BSU9DQ") }
        XCTAssertEqual(r, .init(id: "group.com.melusik.ate.4B39BSU9DQ", source: "profile", available: true))
    }
    func testFallsBackToDefaultThenUnavailable() {
        XCTAssertEqual(AppGroupResolver.resolve(profile: [], alt: [], derived: nil) { $0 == AppGroupResolver.defaultID }.source, "default")
        let none = AppGroupResolver.resolve(profile: ["group.*"], alt: [], derived: nil) { _ in false }
        XCTAssertFalse(none.available); XCTAssertEqual(none.id, AppGroupResolver.defaultID)
    }
    func testAltStoreInfoPlistGroup() {
        let r = AppGroupResolver.resolve(profile: [], alt: ["group.com.melusik.ate.TEAM"], derived: nil) { $0.hasSuffix("TEAM") }
        XCTAssertEqual(r.source, "Info.plist")
    }
    func testExtensionBundleIDMapsToApp() {
        XCTAssertEqual(AppGroupResolver.appBundleID("com.melusik.ate.4B39BSU9DQ.widgets"), "com.melusik.ate.4B39BSU9DQ")
        XCTAssertEqual(AppGroupResolver.appBundleID("com.melusik.ate"), "com.melusik.ate")
    }
    func testParsesProvisioningProfile() {
        let xml = "junk<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Entitlements</key><dict><key>com.apple.security.application-groups</key><array><string>group.x.Y</string></array></dict></dict></plist>junk"
        XCTAssertEqual(AppGroupResolver.profileGroups(Data(xml.utf8)), ["group.x.Y"])
    }
}
