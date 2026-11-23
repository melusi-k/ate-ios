import XCTest
import UIKit
@testable import Ate

/// A generation attempt whose system stream never settles must still reach a terminal
/// state. These tests drive the production attempt seams (beginCoverAttempt /
/// runCoverAttempt / commitGeneratedCover), not copies of their logic: removing the real
/// guards fails them.
@MainActor
final class CoverTerminalDeadlineTests: XCTestCase {

    private func recipe(_ id: String) -> RecipeCard { RecipeCard(id: id, title: "Terminal probe \(id)") }

    private nonisolated func testImage() -> CGImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 6))
        return r.image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 6)) }.cgImage!
    }

    private func generatedCoverExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: CoverStore.url(CoverLogic.fileName(for: id, source: .generated)).path)
    }

    // MARK: deadline helper

    func testNeverSettlingOperationReachesTerminalNilAfterDeadline() async {
        let started = Date()
        let result = await CoverStore.withTerminalDeadline(seconds: 1) { () async -> String? in
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            return "late"
        }
        XCTAssertNil(result, "A hung generation attempt must terminate as failure, not wait forever")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "Terminal state must arrive near the deadline")
    }

    func testSettlingOperationReturnsItsValueBeforeDeadline() async {
        let result = await CoverStore.withTerminalDeadline(seconds: 30) { () async -> String? in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "cover-file"
        }
        XCTAssertEqual(result, "cover-file")
    }

    func testFailingOperationSettlesImmediatelyWithoutWaitingForDeadline() async {
        let started = Date()
        let result = await CoverStore.withTerminalDeadline(seconds: 30) { () async -> String? in nil }
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "A settled failure must not wait for the deadline")
    }

    // MARK: production attempt seams

    /// Through the production runner: the deadline passes, the product materializes
    /// afterwards (cancellation-resistant on purpose), yet it is never committed, and the
    /// shimmer state clears at the terminal state.
    func testDeadlineThenLateCompletionCannotCommit() async {
        let store = CoverStore()
        let r = recipe("cover-terminal-late")
        defer { store.removeFiles(recipeID: r.id) }
        let lateImage = testImage()
        let saved = await store.runCoverAttempt(for: r, seconds: 1) { () async -> CGImage? in
            Thread.sleep(forTimeInterval: 2)  // ignores cancellation: the product is really late
            return lateImage
        }
        XCTAssertNil(saved, "An attempt whose stream settles after the deadline reports failure")
        XCTAssertFalse(store.isLoading(r.id), "loading must clear when the attempt reaches its terminal state")
        try? await Task.sleep(nanoseconds: 3_000_000_000)  // let the late product fully materialize
        XCTAssertFalse(generatedCoverExists(r.id), "A product completing after the deadline must never be written")
    }

    /// Through the production token + commit seam: a superseded attempt's product cannot
    /// commit; only the still-current attempt may write.
    func testSupersededAttemptCannotCommit() {
        let store = CoverStore()
        let r = recipe("cover-terminal-stale")
        defer { store.removeFiles(recipeID: r.id) }
        let stale = store.beginCoverAttempt(for: r)
        let current = store.beginCoverAttempt(for: r)
        XCTAssertNotEqual(stale, current)
        XCTAssertNil(store.commitGeneratedCover(testImage(), attempt: stale, for: r),
                     "A superseded attempt must be ineligible at the effect boundary")
        XCTAssertFalse(generatedCoverExists(r.id))
        XCTAssertNotNil(store.commitGeneratedCover(testImage(), attempt: current, for: r),
                        "The current attempt must commit")
        XCTAssertTrue(generatedCoverExists(r.id))
    }

    /// Through the production commit seam: a writer-epoch rejection after the await drops
    /// the product instead of writing a cover for a replaced store state.
    func testEpochRejectionCannotCommit() {
        let store = CoverStore()
        let r = recipe("cover-terminal-epoch")
        defer { store.removeFiles(recipeID: r.id) }
        let attempt = store.beginCoverAttempt(for: r)
        store.validateWriter = { throw NSError(domain: "CoverTerminalDeadlineTests", code: 1) }
        XCTAssertNil(store.commitGeneratedCover(testImage(), attempt: attempt, for: r),
                     "A failed writer-epoch re-check must block the commit")
        XCTAssertFalse(generatedCoverExists(r.id))
    }

    /// Through the production runner: a producer that fails fast also reaches a terminal
    /// state with the shimmer cleared, without waiting for the deadline.
    func testFailedAttemptClearsLoadingImmediately() async {
        let store = CoverStore()
        let r = recipe("cover-terminal-fail")
        defer { store.removeFiles(recipeID: r.id) }
        let started = Date()
        let saved = await store.runCoverAttempt(for: r, seconds: 30) { () async -> CGImage? in nil }
        XCTAssertNil(saved)
        XCTAssertFalse(store.isLoading(r.id), "loading must clear on a failed attempt")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "A settled failure must not wait for the deadline")
        XCTAssertFalse(generatedCoverExists(r.id))
    }

    /// Overlapping attempts for the same recipe through the production runner: entry and
    /// release gates prove both attempts started before the older one is released, so the
    /// ordering is proven, not assumed. The superseded attempt must not clear the shimmer
    /// while the current attempt runs; the last holder clears it at its terminal state.
    func testSupersededAttemptDoesNotClearLoadingOfCurrentAttempt() async {
        let store = CoverStore()
        let r = recipe("cover-terminal-overlap")
        defer { store.removeFiles(recipeID: r.id) }
        let olderEntered = TestGate(), olderRelease = TestGate()
        let newerEntered = TestGate(), newerRelease = TestGate()
        let older = Task { await store.runCoverAttempt(for: r, seconds: 30) { () async -> CGImage? in
            olderEntered.open()
            await olderRelease.awaitOpen()
            return nil
        } }
        await olderEntered.awaitOpen()  // proof: the older attempt is inside its producer
        XCTAssertTrue(store.isLoading(r.id))
        let newer = Task { await store.runCoverAttempt(for: r, seconds: 30) { () async -> CGImage? in
            newerEntered.open()
            await newerRelease.awaitOpen()
            return nil
        } }
        await newerEntered.awaitOpen()  // proof: the newer attempt started and superseded
        olderRelease.open()             // the older attempt now settles while the newer runs
        let olderResult = await older.value
        XCTAssertNil(olderResult)
        XCTAssertTrue(store.isLoading(r.id),
                      "A superseded attempt must not clear the shimmer while the current attempt runs")
        newerRelease.open()
        let newerResult = await newer.value
        XCTAssertNil(newerResult)
        XCTAssertFalse(store.isLoading(r.id),
                       "The last holder clears the shimmer at its own terminal state")
    }

    /// Nested ownership across resolve and an attempt on the same recipe: while an attempt
    /// holds the shimmer (proven inside its producer via gates), a full resolve call comes
    /// and goes; its completion must not clear the attempt's shimmer. On the old
    /// unconditional `defer { loading.remove }` in resolve this fails.
    func testResolveCompletionDoesNotClearOverlappingAttemptShimmer() async {
        let store = CoverStore()
        let r = recipe("cover-terminal-resolve-overlap")
        defer { store.removeFiles(recipeID: r.id) }
        let attemptEntered = TestGate(), attemptRelease = TestGate()
        let attempt = Task { await store.runCoverAttempt(for: r, seconds: 30) { () async -> CGImage? in
            attemptEntered.open()
            await attemptRelease.awaitOpen()
            return nil
        } }
        await attemptEntered.awaitOpen()  // proof: the attempt holds the shimmer
        XCTAssertTrue(store.isLoading(r.id))
        // A whole resolve runs while the attempt holds: no web paths, generation disabled,
        // so it completes inside its own scope without touching the network.
        let resolved = await store.resolve(r, allowGenerate: false)
        XCTAssertNil(resolved)
        XCTAssertTrue(store.isLoading(r.id),
                      "resolve releasing its own hold must not clear the attempt's shimmer")
        attemptRelease.open()
        let attemptResult = await attempt.value
        XCTAssertNil(attemptResult)
        XCTAssertFalse(store.isLoading(r.id), "The last holder clears the shimmer")
    }
}

/// One-shot gate: producers signal entry and wait for release, so tests prove ordering
/// instead of assuming it with sleeps.
private final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
    func awaitOpen() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
