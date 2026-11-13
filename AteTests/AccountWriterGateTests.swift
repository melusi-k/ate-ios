import XCTest
@testable import Ate

@MainActor
final class AccountWriterGateTests: XCTestCase {
    private func fixture(_ run: (URL) throws -> Void) throws {
        // The stores under test REQUIRE a canonical directory: standardizedFileURL
        // identity, no symlink components. NSTemporaryDirectory may traverse a
        // symlinked ancestor (/var -> /private/var on Apple hosts), so resolve the
        // fixture root AFTER creating it. Production guards stay unchanged.
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let directory = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }
    func testTwoInstancesShareEpochAndResetExcludesWriterEffect() throws {
        try fixture { directory in
            let first = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let second = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let lease = try first.captureWriter()
            XCTAssertEqual(try second.captureWriter(), lease)
            try second.acquireResetGate()
            defer { second.releaseResetGate() }
            var effect = false
            XCTAssertThrowsError(try first.withWriterEffect(lease) { effect = true })
            XCTAssertFalse(effect)
        }
    }
    func testOldLeaseRemainsInvalidAfterResetReleases() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let old = try gate.captureWriter()
            try gate.acquireResetGate(); gate.releaseResetGate()
            XCTAssertThrowsError(try gate.validateWriter(old))
            XCTAssertNotEqual(try gate.captureWriter(), old)
        }
    }
    func testRetainedControlBlocksBetweenResetAttempts() throws {
        try fixture { directory in
            var pending = false
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { pending })
            let old = try gate.captureWriter()
            try gate.acquireResetGate(); pending = true; gate.releaseResetGate()
            XCTAssertThrowsError(try gate.captureWriter())
            XCTAssertThrowsError(try gate.withWriterEffect(old) { XCTFail("effect while reset pending") })
        }
    }
    func testSameOwnerSessionInvalidationRejectsOldAsyncLease() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let old = try gate.captureWriter()
            try gate.invalidateWriters()
            XCTAssertThrowsError(try gate.validateWriter(old))
        }
    }
    func testCorruptEpochIsNeverFreshAdmission() throws {
        try fixture { directory in
            try Data("broken".utf8).write(to: directory.appendingPathComponent("writer-epoch-v1"))
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            XCTAssertThrowsError(try gate.captureWriter())
            XCTAssertThrowsError(try gate.acquireResetGate())
        }
    }
    func testDroppingActiveResetGateReleasesOSLockButKeepsOldEpochInvalid() throws {
        try fixture { directory in
            var first: AccountWriterGate? = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let old = try first!.captureWriter()
            try first!.acquireResetGate()
            weak var weakFirst = first
            first = nil
            XCTAssertNil(weakFirst)
            let second = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let next = try second.captureWriter()
            XCTAssertNotEqual(next, old)
            XCTAssertThrowsError(try second.validateWriter(old))
        }
    }

    func testSynchronousNestedGraphWriterUsesSameHeldLease() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let lease = try gate.captureWriter()
            try gate.withWriterEffect(lease) {
                XCTAssertEqual(try gate.captureWriter(), lease)
                try gate.withWriterEffect(lease) {}
                XCTAssertThrowsError(try gate.withWriterEffect(UUID()) {})
            }
            try gate.validateWriter(lease)
        }
    }

}

extension AccountWriterGateTests {
    func testGenerationConflictBlocksOriginalAndNewLeasesAcrossInstancesAndRelaunch() throws {
        try fixture { directory in
            var first: AccountWriterGate? = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let sibling = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let old = try first!.captureWriter()
            try first!.blockWritersForGenerationConflict()
            XCTAssertThrowsError(try first!.validateWriter(old))
            XCTAssertThrowsError(try first!.captureWriter())
            XCTAssertThrowsError(try sibling.withWriterEffect(old) { XCTFail("sibling wrote after conflict") })
            XCTAssertThrowsError(try sibling.captureWriter())
            XCTAssertThrowsError(try sibling.acquireResetGate(), "ordinary reset cannot discard unresolved conflict")
            first = nil
            let relaunched = try AccountWriterGate(directory: directory, resetControlExists: { false })
            XCTAssertThrowsError(try relaunched.captureWriter())
            try relaunched.invalidateWriters() // rotating epoch does NOT clear the block
            XCTAssertThrowsError(try relaunched.captureWriter())
        }
    }

    func testCorruptOrSymlinkConflictMarkerIsNeverFreshAdmission() throws {
        try fixture { directory in
            let file = directory.appendingPathComponent("writer-generation-block-v1")
            try Data("broken".utf8).write(to: file)
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            XCTAssertThrowsError(try gate.captureWriter())
            XCTAssertThrowsError(try gate.acquireResetGate())
            try FileManager.default.removeItem(at: file)
            let target = directory.appendingPathComponent("outside")
            try Data(UUID().uuidString.utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertThrowsError(try gate.captureWriter())
            XCTAssertThrowsError(try gate.blockWritersForGenerationConflict())
        }
    }
}
