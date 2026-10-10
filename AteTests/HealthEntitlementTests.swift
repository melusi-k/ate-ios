import XCTest
@testable import Ate

/// A-HEALTH-01: the real (sideload) IPA is signed with Ate.entitlements, so it must carry HealthKit or
/// Connect Apple Health can never show the permission sheet.
final class HealthEntitlementTests: XCTestCase {
    private func plist(_ rel: String, file: StaticString = #filePath) throws -> [String: Any] {
        let root = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(rel))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testEntitlementFilesContainHealthKit() throws {
        for f in ["Ate/Ate.entitlements", "Ate/Ate-Signed.entitlements"] {
            let p = try plist(f)
            XCTAssertEqual(p["com.apple.developer.healthkit"] as? Bool, true, f)
            XCTAssertEqual((p["com.apple.developer.healthkit.access"] as? [Any])?.count, 0, f)
        }
    }

    func testHealthDiagnosticsRecordsLastResult() {
        HealthDiagnostics.record("error: test")
        XCTAssertEqual(HealthDiagnostics.lastResult, "error: test")
        XCTAssertTrue(HealthDiagnostics.line.contains("last request=error: test"))
        XCTAssertNotNil(MockHealthKitService(scenario: "noEntitlement").lastError)
        XCTAssertNil(MockHealthKitService(scenario: "recovery").lastError)
    }
}
