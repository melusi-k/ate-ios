import XCTest
@testable import Ate

final class GenerationCancellationTests: XCTestCase {
    enum Failure: Error { case decoding }

    func testCancellationAndCancelledTransportStayInterrupted() {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            XCTAssertThrowsError(try GenerationCancellation.check(error)) {
                XCTAssertTrue($0 is CancellationError)
            }
        }
        XCTAssertNoThrow(try GenerationCancellation.check(Failure.decoding))
        XCTAssertNoThrow(try GenerationCancellation.check(URLError(.notConnectedToInternet)))
    }

    func testCancelledRepairCannotPublishOriginalCard() async {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            do {
                _ = try await GenerationCancellation.optionalRepair(original: "partial card", operation: { throw error }, prefer: { _, _ in true })
                XCTFail("Cancelled repair must not silently return original recipe")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    func testOrdinaryRepairFailureRetainsFirstResult() async throws {
        let value = try await GenerationCancellation.optionalRepair(original: "first card", operation: { throw Failure.decoding }, prefer: { _, _ in true })
        XCTAssertEqual(value, "first card")
    }

    func testQualityRepairStillUsesOnlyBetterResult() async throws {
        let better = try await GenerationCancellation.optionalRepair(original: 1, operation: { 2 }, prefer: { $0 > $1 })
        let worse = try await GenerationCancellation.optionalRepair(original: 2, operation: { 1 }, prefer: { $0 > $1 })
        XCTAssertEqual(better, 2)
        XCTAssertEqual(worse, 2)
    }

    func testAlreadyCancelledTaskDoesNotStartRepair() async {
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            var started = false
            do {
                _ = try await GenerationCancellation.optionalRepair(original: 1, operation: { started = true; return 2 }, prefer: { _, _ in true })
                XCTFail("Cancelled attempt must not start another model operation")
            } catch { XCTAssertTrue(error is CancellationError) }
            return started
        }
        let started = await task.value
        XCTAssertFalse(started)
    }

    func testCancellationAfterCooperativeBoundaryRejectsEvenReturnedResult() async {
        let task = Task { () -> Bool in
            do {
                _ = try await GenerationCancellation.optionalRepair(original: 1, operation: {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return 2 // models a provider that ignores cancellation and returns success
                }, prefer: { _, _ in true })
                return true
            } catch {
                XCTAssertTrue(error is CancellationError)
                return false
            }
        }
        let published = await task.value
        XCTAssertFalse(published)
    }
}
