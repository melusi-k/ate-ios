import XCTest
import UserNotifications
@testable import Ate

/// The blocker stands in for the exact synchronous daemon stall in the retained
/// stackshots. It does not return instant success. The production worker and its
/// cancel/add/clear ordering are exercised without changing any OS timeout.
final class TimerNotificationWorkerTests: XCTestCase {
    private final class Events {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
        var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return values }
    }
    private func request(_ id: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Step 1 is done"
        content.body = "Soup"
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false))
    }

    @MainActor
    func testBlockedDaemonCancelReturnsToCallerAndKeepsCancelScheduleStopOrder() async {
        let entered = expectation(description: "daemon cancel entered")
        let finished = expectation(description: "stop submitted after schedule")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let events = Events()
        let request = request("ate.timer.soup#0")
        let worker = TimerNotificationWorker(remove: { id in
            XCTAssertFalse(Thread.isMainThread)
            if events.snapshot.isEmpty {
                events.append("cancel-before-schedule:" + id)
                entered.fulfill()
                gate.wait() // An unresponsive synchronous service, not a fast mock.
            } else {
                events.append("stop:" + id)
                finished.fulfill()
            }
        }, add: { received, done in
            events.append("schedule:" + received.identifier)
            XCTAssertEqual(received.content.title, "Step 1 is done")
            XCTAssertEqual(received.content.body, "Soup")
            done()
        }, clearAndVerify: { _ in XCTFail("Unexpected clear") })
        worker.replace(identifier: request.identifier, request: { request })
        // This MainActor test reaches the wait while daemon cancellation is blocked.
        // Running removal inline would prevent even this assertion/continuation.
        await fulfillment(of: [entered], timeout: 2)
        worker.cancel(identifier: request.identifier)
        XCTAssertEqual(events.snapshot, ["cancel-before-schedule:ate.timer.soup#0"])
        gate.signal()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(events.snapshot, ["cancel-before-schedule:ate.timer.soup#0",
                                         "schedule:ate.timer.soup#0", "stop:ate.timer.soup#0"])
    }

    @MainActor
    func testClearAllWaitsForAdmittedAddCompletionThenVerifiesWithoutLateRepopulation() async {
        let addEntered = expectation(description: "add entered")
        let releaseAdd = DispatchSemaphore(value: 0)
        defer { releaseAdd.signal() }
        let cleared = expectation(description: "clear and verification order")
        let events = Events()
        let request = request("ate.timer.soup#0")
        let worker = TimerNotificationWorker(remove: { _ in events.append("cancel") }, add: { _, done in
            events.append("add-enter")
            addEntered.fulfill()
            DispatchQueue.global().async {
                releaseAdd.wait()
                events.append("add-complete")
                done()
            }
        }, clearAndVerify: { done in
            events.append("remove-all-pending-and-delivered")
            events.append("verify")
            done(true)
            cleared.fulfill()
        })
        worker.replace(identifier: request.identifier, request: { request })
        await fulfillment(of: [addEntered], timeout: 2)
        // Synchronous admission guarantees this barrier is queued while add is
        // still incomplete, without relying on when a child Task is scheduled.
        worker.removeAllAndVerify { verified in XCTAssertTrue(verified) }
        XCTAssertEqual(events.snapshot, ["cancel", "add-enter"])
        releaseAdd.signal()
        await fulfillment(of: [cleared], timeout: 2)
        XCTAssertEqual(events.snapshot, ["cancel", "add-enter", "add-complete",
                                         "remove-all-pending-and-delivered", "verify"])
    }

    func testCancelOnlyDoesNotAddAndFailedClearVerificationStaysFalse() async {
        let cancelled = expectation(description: "cancel only")
        let events = Events()
        let worker = TimerNotificationWorker(remove: { id in
            events.append("cancel:" + id)
            cancelled.fulfill()
        }, add: { _, _ in XCTFail("Cancellation must not schedule") }, clearAndVerify: { done in
            events.append("verify-failed")
            done(false)
        })
        worker.cancel(identifier: "ate.timer.soup#0")
        await fulfillment(of: [cancelled], timeout: 2)
        let verified = await worker.removeAllAndVerify()
        XCTAssertFalse(verified)
        XCTAssertEqual(events.snapshot, ["cancel:ate.timer.soup#0", "verify-failed"])
    }
}
