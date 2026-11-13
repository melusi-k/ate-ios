import XCTest
@testable import Ate

@MainActor
final class FoodJournalConsumerTasksTests: XCTestCase {
    private func fixture(_ run: (FoodJournalConsumerLifecycle, FoodJournalConsumerTasks) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConsumerTasks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lifecycle = FoodJournalConsumerLifecycle(gate: gate, admittedLease: try gate.captureWriter(),
            session: nil, currentSession: { nil })
        try await run(lifecycle, FoodJournalConsumerTasks(lifecycle: lifecycle))
    }

    func testQuiescenceAwaitsCancellationIgnoringWorkAndRefusesLatePublication() async throws {
        try await fixture { lifecycle, tasks in
            var started: CheckedContinuation<Void, Never>?
            var release: CheckedContinuation<Void, Never>?
            var finished = false, published = false, drained = false
            let worker = Task { @MainActor in
                do {
                    try await tasks.run {
                        await withCheckedContinuation { release = $0; started?.resume(); started = nil }
                        finished = true
                    }
                    published = true
                } catch { }
            }
            await withCheckedContinuation { continuation in
                if release != nil { continuation.resume() } else { started = continuation }
            }
            let cancellationStarted = expectation(description: "owner cancellation started")
            try lifecycle.register(cancel: { cancellationStarted.fulfill() }, drain: {})
            let closing = Task { @MainActor in try await lifecycle.quiesce(); drained = true }
            await fulfillment(of: [cancellationStarted], timeout: 2)
            XCTAssertFalse(drained, "Cancellation is not proof the task drained")
            XCTAssertFalse(finished)
            release?.resume(); release = nil
            try await closing.value
            await worker.value
            XCTAssertTrue(finished, "Even cancellation-ignoring work must finish before quiesced")
            XCTAssertTrue(drained)
            XCTAssertFalse(published, "A completed old task cannot publish under the closed owner")
            XCTAssertEqual(lifecycle.state, .quiesced)
        }
    }

    func testClosedOwnerRejectsNewWorkBeforeItsBodyRuns() async throws {
        try await fixture { lifecycle, tasks in
            try await lifecycle.quiesce()
            var ran = false
            do {
                try await tasks.run { ran = true }
                XCTFail("Closed owner must refuse tasks")
            } catch { }
            XCTAssertFalse(ran)
        }
    }

    func testCapturedSharedOwnerCannotRebindToReplacementAfterAwait() async throws {
        try await fixture { lifecycle, _ in
            var oldEffects = 0, newEffects = 0
            let old = SharedWriterBoundary { work in try lifecycle.validate(); oldEffects += 1; try work() }
            let replacement = SharedWriterBoundary { work in newEffects += 1; try work() }
            let tasks = FoodJournalConsumerTasks(lifecycle: lifecycle, sharedBoundary: old)
            var release: CheckedContinuation<Void, Never>?
            let started = expectation(description: "old shared task suspended")
            let finished = expectation(description: "old shared task finished")
            var staleWrite = false
            let runner = Task { @MainActor in
                defer { finished.fulfill() }
                do {
                    try await tasks.run {
                        await withCheckedContinuation { release = $0; started.fulfill() }
                        // Work deliberately ignores cancellation. Task-local owner
                        // identity remains old even under a replacement UI context.
                        do { try SharedWriterBoundary.current.withEffect { staleWrite = true } }
                        catch { }
                    }
                } catch { }
            }
            await fulfillment(of: [started], timeout: 2)
            let closing = Task { @MainActor in try await lifecycle.quiesce() }
            while lifecycle.state == .active { await Task.yield() }
            try SharedWriterBoundary.withCapturedOwner(replacement) {
                try SharedWriterBoundary.current.withEffect { }
                release?.resume(); release = nil
            }
            try await closing.value
            await runner.value
            await fulfillment(of: [finished], timeout: 2)
            XCTAssertFalse(staleWrite)
            XCTAssertEqual(oldEffects, 0)
            XCTAssertEqual(newEffects, 1)
        }
    }

    func testOrdinaryBoundaryCapturesSharedOwnerAndUnownedDefaultRefuses() throws {
        SharedWriterBoundary.resetForTesting()
        defer { SharedWriterBoundary.resetForTesting() }
        XCTAssertTrue(SharedWriterBoundary.install(.requiresCapturedOwner))
        XCTAssertThrowsError(try SharedWriterBoundary.current.withEffect { XCTFail("Unowned write") })
        var effects = 0
        let owner = FoodJournalWriterBoundary(captureSharedWrites: true) { work in effects += 1; try work() }
        try owner.withEffect { try SharedWriterBoundary.current.withEffect { } }
        XCTAssertEqual(effects, 1, "Shared nested effect uses original owner without another flock")
        XCTAssertThrowsError(try SharedWriterBoundary.current.withEffect { XCTFail("Context must not escape") })
    }

    func testDraftWriterRetainsOriginalBoundaryAfterReplacement() throws {
        let suite = "OwnedDraft-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var active = true
        enum Closed: Error { case owner }
        let boundary = FoodJournalWriterBoundary { work in
            guard active else { throw Closed.owner }
            try work()
        }
        let old = DraftStore(defaults: defaults, enabled: true, writerBoundary: boundary)
        old.begin(mode: "prompt", text: "original")
        XCTAssertEqual(old.pending?.text, "original")
        active = false
        let replacement = DraftStore(defaults: defaults, enabled: true)
        replacement.begin(mode: "prompt", text: "replacement")
        old.clear()
        old.begin(mode: "prompt", text: "stale")
        XCTAssertEqual(replacement.pending?.text, "replacement")
    }
}
