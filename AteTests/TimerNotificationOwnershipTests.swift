import XCTest
import UserNotifications
@testable import Ate

@MainActor
final class TimerNotificationOwnershipTests: XCTestCase {
    func testOwnerCloseDrainsCancellationIgnoringAddBeforeCleanup() async throws {
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "OS add suspended")
        var ids = Set<String>()
        let queue = OrderedTimerNotifications(add: { request in
            await withCheckedContinuation { release = $0; started.fulfill() }
            ids.insert(request.identifier)
        }, remove: { ids.subtract($0) })
        let request = UNNotificationRequest(identifier: "ate.timer.fixture", content: UNMutableNotificationContent(), trigger: nil)
        queue.schedule(request)
        await fulfillment(of: [started], timeout: 2)
        queue.closeOwner()
        var drained = false
        let drain = Task { @MainActor in await queue.drainOwner(); drained = true }
        await Task.yield()
        XCTAssertFalse(drained)
        // New work cannot join the closed owner.
        queue.schedule(UNNotificationRequest(identifier: "ate.timer.new", content: UNMutableNotificationContent(), trigger: nil))
        release?.resume(); release = nil
        await drain.value
        XCTAssertTrue(drained)
        XCTAssertTrue(ids.isEmpty, "Late completed add is removed before drain reports done")
    }

    func testCancelIsOrderedAfterEarlierSuspendedAdd() async throws {
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "OS add suspended")
        var ids = Set<String>()
        let queue = OrderedTimerNotifications(add: { request in
            await withCheckedContinuation { release = $0; started.fulfill() }
            ids.insert(request.identifier)
        }, remove: { ids.subtract($0) })
        queue.schedule(UNNotificationRequest(identifier: "ate.timer.fixture", content: UNMutableNotificationContent(), trigger: nil))
        await fulfillment(of: [started], timeout: 2)
        queue.cancel("ate.timer.fixture")
        release?.resume(); release = nil
        await queue.drainOwner()
        XCTAssertTrue(ids.isEmpty)
    }

    func testUnresolvedCrossProcessSubmissionBlocksResetAndAuthRotation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let originalLease = try gate.captureWriter()
        let shared = try SharedFileWriterGate(directory: root, resetPending: { false }, archive: .none).makeBoundary()
        let token = try shared.withEffect { try SharedNotificationSubmission.begin(directory: root) }
        XCTAssertThrowsError(try gate.acquireResetGate())
        XCTAssertThrowsError(try gate.invalidateWriters())
        XCTAssertThrowsError(try gate.invalidateWriters(expectedLease: originalLease))
        XCTAssertThrowsError(try shared.withEffect { try SharedNotificationSubmission.begin(directory: root) })
        try token.finish()
        try gate.acquireResetGate()
        try gate.validateResetGate()
        gate.releaseResetGate()
        XCTAssertThrowsError(try shared.withEffect { XCTFail("Original extension cannot resume after reset") })
    }
}
