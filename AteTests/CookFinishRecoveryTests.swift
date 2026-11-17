import XCTest
@testable import Ate

final class CookFinishRecoveryTests: XCTestCase {
    func testNoRequestMeansDismissalDoesNotRetryOrSetAside() {
        var recovery = CookFinishRecovery()
        XCTAssertNil(recovery.consume())
        XCTAssertNil(recovery.consume())
    }
    func testEachExplicitRetryIsConsumedOnceOnly() {
        var recovery = CookFinishRecovery()
        recovery.request(.retry)
        XCTAssertEqual(recovery.consume(), .retry)
        XCTAssertNil(recovery.consume())
        recovery.request(.retry)
        XCTAssertEqual(recovery.consume(), .retry)
        XCTAssertNil(recovery.consume())
    }
    func testSetAsideIsSeparateFromRetryAndConsumedOnce() {
        var recovery = CookFinishRecovery()
        recovery.request(.setAside)
        XCTAssertEqual(recovery.consume(), .setAside)
        XCTAssertNil(recovery.consume())
    }
    func testUserRetryKeepsFirstQueuedPayloadAcrossDayAndTitleChanges() throws {
        let name = "CookFinishRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let outbox = CookCompletionOutbox(defaults: defaults)
        let first = CookCompletionEvent(recipeID: "recipe", recipeTitle: "Original title", completedAt: Date(timeIntervalSince1970: 0), dayKey: "1970-01-01", id: "cook-same-session")
        let later = CookCompletionEvent(recipeID: "recipe", recipeTitle: "Changed title", completedAt: Date(timeIntervalSince1970: 86400), dayKey: "1970-01-02", id: "cook-same-session")
        try outbox.enqueue(first)
        var recovery = CookFinishRecovery()
        recovery.request(.retry)
        guard recovery.consume() == .retry else { return XCTFail("Explicit retry must be consumed") }
        XCTAssertEqual(try outbox.enqueue(later), first)
        XCTAssertEqual(try outbox.load(), [first])
        XCTAssertNil(recovery.consume(), "No automatic retry after the explicit attempt")
    }
}
