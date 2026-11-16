import XCTest
import Security
@testable import Ate

final class KeychainStatusDiagnosticTests: XCTestCase {
    func testCapturesEveryResultExactlyOnceAndReturnsItUnchanged() {
        let diagnostic = KeychainStatusDiagnostic()
        var calls = 0
        for status in [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement,
                       errSecInteractionNotAllowed, errSecParam, errSecAuthFailed] {
            XCTAssertEqual(diagnostic.capture(.update) { calls += 1; return status }, status)
        }
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(diagnostic.summary,
                       [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement,
                        errSecInteractionNotAllowed, errSecParam, errSecAuthFailed]
                        .map { "update:\($0)" }.joined(separator: ","))
    }

    func testKeepsOperationSequenceBoundedAndProcessLocal() {
        let diagnostic = KeychainStatusDiagnostic()
        diagnostic.capture(.delete) { errSecSuccess }
        for _ in 0..<KeychainStatusDiagnostic.maximumEntries {
            diagnostic.capture(.read) { errSecItemNotFound }
        }
        XCTAssertEqual(diagnostic.summary.split(separator: ",").count, 24)
        XCTAssertFalse(diagnostic.summary.contains("delete"))
        diagnostic.capture(.update) { errSecItemNotFound }
        diagnostic.capture(.add) { errSecMissingEntitlement }
        XCTAssertTrue(diagnostic.summary.hasSuffix("update:\(errSecItemNotFound),add:\(errSecMissingEntitlement)"))
        XCTAssertEqual(KeychainStatusDiagnostic().summary, "")
    }
}
