import XCTest
@testable import Ate

@MainActor
final class SystemCleanupCompletionTests: XCTestCase {
    private final class CallbackBox: @unchecked Sendable {
        var callback: (@Sendable (Bool) -> Void)?
    }

    func testImmediateVerifiedSuccessAndFailureArePreserved() async {
        let success = await SystemCleanupCompletion.wait(timeout: 1) { $0(true) }
        let failure = await SystemCleanupCompletion.wait(timeout: 1) { $0(false) }
        XCTAssertTrue(success)
        XCTAssertFalse(failure)
    }

    func testDuplicateAndLateCallbacksCannotResumeTwice() async {
        let value = await SystemCleanupCompletion.wait(timeout: 1) { finish in
            finish(false)
            finish(true)
        }
        XCTAssertFalse(value)
    }

    func testNeverReturningServiceReleasesWaitAsUnverified() async {
        let value = await SystemCleanupCompletion.wait(timeout: 0.02) { _ in }
        XCTAssertFalse(value, "No callback must never mean deletion succeeded")
    }

    func testLateSuccessAfterDeadlineStaysUnverified() async {
        let box = CallbackBox()
        let value = await SystemCleanupCompletion.wait(timeout: 0.02) { box.callback = $0 }
        XCTAssertFalse(value)
        box.callback?(true)
        box.callback?(false)
    }

    func testCancellationReleasesUncooperativeWaitAndIgnoresLateReply() async {
        let box = CallbackBox()
        let started = expectation(description: "service registered")
        let worker = Task { @MainActor in
            await SystemCleanupCompletion.wait(timeout: 60) { callback in
                box.callback = callback
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        worker.cancel()
        let value = await worker.value
        XCTAssertFalse(value)
        box.callback?(true)
    }

    func testAlreadyCancelledWaitDoesNotStartService() async {
        let worker = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await SystemCleanupCompletion.wait(timeout: 60) { _ in
                XCTFail("cancelled attempt must not register a new deletion")
            }
        }
        let value = await worker.value
        XCTAssertFalse(value)
    }

    func testInvalidDeadlineDoesNotStartService() async {
        for timeout in [0, -1, Double.infinity, Double.nan] {
            let value = await SystemCleanupCompletion.wait(timeout: timeout) { _ in XCTFail("invalid deadline") }
            XCTAssertFalse(value)
        }
    }

    func testCleanupMissingSpotlightCallbackReportsSurfaceWithoutDiscardingSnapshotAssertions() async throws {
        let name = "ate.cleanup.deadline.\(UUID().uuidString)"
        let shared = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { shared.removePersistentDomain(forName: name) }
        shared.set(["retained": 1], forKey: WidgetSnapshot.key)
        shared.set(["retained": 1], forKey: WidgetKinds.heartbeatKey)
        shared.set("nonData", forKey: TimerSnapshot.key)
        let cleaner = SystemSurfaceCleanup(timers: TimerCenter(), sharedDefaults: shared,
            spotlightTimeout: 0.02, deleteSpotlight: { _ in })
        let failures = await cleaner.cleanupAfterLocalErase()
        XCTAssertTrue(failures.contains(SystemSurfaceCleanup.Surface.spotlight))
        XCTAssertFalse(failures.contains(SystemSurfaceCleanup.Surface.widgetSnapshots))
        XCTAssertNil(shared.object(forKey: WidgetSnapshot.key))
        XCTAssertNil(shared.object(forKey: WidgetKinds.heartbeatKey))
        XCTAssertNil(shared.object(forKey: TimerSnapshot.key))
    }
}
