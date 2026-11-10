import XCTest
@testable import Ate

/// Focused source tests for the lane 2 Shared shim (#245): the strict
/// reset-control existence reader, the POSIX UInt64 generation chain in its
/// no-flock nested mode, the unresolved txn-name admission check, the nested
/// archive unit, and the one-call extension composition.
@MainActor
final class SharedStrictPersistenceTests: XCTestCase {
    private func withDirectory(_ run: (URL) throws -> Void) throws {
        // The lease walks the path from "/" with O_NOFOLLOW: resolve symlinks
        // (/var -> /private/var on Apple hosts) BEFORE creating the fixture.
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("SharedStrictPersistenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let directory = url.standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    private func generationName(_ n: UInt64) -> String { String(format: ".generation-%020llu", n) }

    @discardableResult
    private func makeTransaction(_ id: UUID = UUID(), in directory: URL, name: String? = nil) throws -> UUID {
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(name ?? "txn-" + id.uuidString),
            withIntermediateDirectories: false)
        return id
    }

    // MARK: 1. Strict reset-control existence reader

    func testResetControlMissingIsAbsent() throws {
        try withDirectory { directory in
            XCTAssertFalse(try SharedResetControl.exists(directory: directory))
            XCTAssertNil(try SharedResetControl.read(directory: directory))
        }
    }

    func testResetControlPresentIsDetected() throws {
        try withDirectory { directory in
            let bytes = Data("{\"reset\":true}".utf8)
            try bytes.write(to: directory.appendingPathComponent(SharedResetControl.fileName))
            XCTAssertTrue(try SharedResetControl.exists(directory: directory))
            XCTAssertEqual(try SharedResetControl.read(directory: directory), bytes)
        }
    }

    func testResetControlPresentButUnreadableRefuses() throws {
        try withDirectory { directory in
            // A directory where the record file belongs is present but not a
            // regular record: refuse, never treat as absent.
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(SharedResetControl.fileName),
                withIntermediateDirectories: false)
            XCTAssertThrowsError(try SharedResetControl.exists(directory: directory)) {
                XCTAssertEqual($0 as? SharedResetControlError, .corruptRecord)
            }
        }
    }

    func testResetControlMissingParentRefuses() throws {
        let missing = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("SharedStrictPersistenceTests-absent-" + UUID().uuidString)
        XCTAssertThrowsError(try SharedResetControl.exists(directory: missing)) {
            XCTAssertEqual($0 as? SharedResetControlError, .persistenceUnverified)
        }
    }

    func testResetControlSymlinkDirectoryRefuses() throws {
        try withDirectory { directory in
            let real = directory.appendingPathComponent("real")
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
            let link = directory.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            XCTAssertThrowsError(try SharedResetControl.exists(directory: link)) {
                XCTAssertEqual($0 as? SharedResetControlError, .persistenceUnverified)
            }
        }
    }

    // MARK: 2. POSIX UInt64 generation chain, no-flock nested mode

    func testNestedLeaseCommitsSequentiallyAndReopens() throws {
        try withDirectory { directory in
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            XCTAssertEqual(lease.generation, 0)
            try lease.commitGeneration(1)
            XCTAssertEqual(lease.generation, 1)
            try lease.validate()
            lease.release()
            let reopened = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { reopened.release() }
            XCTAssertEqual(reopened.generation, 1)
            try reopened.commitGeneration(2)
            XCTAssertEqual(reopened.generation, 2)
        }
    }

    func testNestedLeaseRefusesOutOfSequenceCommit() throws {
        try withDirectory { directory in
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertThrowsError(try lease.commitGeneration(2)) {
                XCTAssertNotNil($0 as? POSIXArchiveWriterLease.Failure)
                guard case .unsafeFile? = ($0 as? POSIXArchiveWriterLease.Failure) else {
                    return XCTFail("expected unsafeFile, got \($0)")
                }
            }
            XCTAssertEqual(lease.generation, 0)
            XCTAssertNoThrow(try lease.validate())
        }
    }

    func testGenerationChainGapRefusesOnOpen() throws {
        try withDirectory { directory in
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            try lease.commitGeneration(1)
            lease.release()
            // Hand-craft a valid generation-3 record so the chain reads 1, 3.
            let name = generationName(3)
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
            XCTAssertThrowsError(try POSIXArchiveWriterLease(nestedDirectory: directory)) {
                XCTAssertNotNil($0 as? POSIXArchiveWriterLease.Failure)
                guard case .unsafeFile? = ($0 as? POSIXArchiveWriterLease.Failure) else {
                    return XCTFail("expected unsafeFile, got \($0)")
                }
            }
        }
    }

    func testMalformedGenerationNameRefuses() throws {
        try withDirectory { directory in
            try Data("junk".utf8).write(to: directory.appendingPathComponent(".generation-abc"))
            XCTAssertThrowsError(try POSIXArchiveWriterLease(nestedDirectory: directory)) {
                XCTAssertNotNil($0 as? POSIXArchiveWriterLease.Failure)
                guard case .unsafeFile? = ($0 as? POSIXArchiveWriterLease.Failure) else {
                    return XCTFail("expected unsafeFile, got \($0)")
                }
            }
        }
    }

    func testNestedModeOpensAndFlocksNoLockFile() throws {
        try withDirectory { directory in
            let nested = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { nested.release() }
            // A standalone lease can still take the lifetime flock while the nested
            // lease is held: nested mode opened and flocked nothing.
            let standalone = try POSIXArchiveWriterLease(directory: directory)
            defer { standalone.release() }
            XCTAssertNoThrow(try nested.validate())
        }
    }

    // MARK: 3. Unresolved txn-name admission check

    func testNoTransactionsAdmitsClean() throws {
        try withDirectory { directory in
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertEqual(try lease.unresolvedTransactionIDs(), [])
            XCTAssertFalse(try lease.hasUnresolvedTransactions())
        }
    }

    func testWellFormedTransactionNameIsReportedUnresolved() throws {
        try withDirectory { directory in
            let first = try makeTransaction(in: directory)
            let second = try makeTransaction(in: directory)
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertEqual(try lease.unresolvedTransactionIDs(),
                           [first, second].sorted { $0.uuidString < $1.uuidString })
            XCTAssertTrue(try lease.hasUnresolvedTransactions())
        }
    }

    func testMalformedTransactionNameRefuses() throws {
        try withDirectory { directory in
            _ = try makeTransaction(in: directory, name: "txn-not-a-uuid")
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertThrowsError(try lease.unresolvedTransactionIDs()) {
                XCTAssertNotNil($0 as? POSIXArchiveWriterLease.Failure)
                guard case .unsafeFile? = ($0 as? POSIXArchiveWriterLease.Failure) else {
                    return XCTFail("expected unsafeFile, got \($0)")
                }
            }
        }
    }

    func testNonCanonicalTransactionNameRefuses() throws {
        try withDirectory { directory in
            // Lowercase uuid text parses as a UUID but is not the canonical name.
            _ = try makeTransaction(in: directory, name: "txn-" + UUID().uuidString.lowercased())
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertThrowsError(try lease.unresolvedTransactionIDs()) {
                XCTAssertNotNil($0 as? POSIXArchiveWriterLease.Failure)
                guard case .unsafeFile? = ($0 as? POSIXArchiveWriterLease.Failure) else {
                    return XCTFail("expected unsafeFile, got \($0)")
                }
            }
        }
    }

    func testResolvedAndUnrelatedNamesAreIgnored() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(".resolved-" + UUID().uuidString),
                withIntermediateDirectories: false)
            try Data("note".utf8).write(to: directory.appendingPathComponent("notes.txt"))
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertFalse(try lease.hasUnresolvedTransactions())
        }
    }

    // MARK: Nested archive unit

    func testNestedUnitRunsWorkAndAdvancesOncePerCommittedUnit() throws {
        try withDirectory { directory in
            var runs = 0
            try SharedArchiveNestedUnit.run(directory: directory) { runs += 1 }
            try SharedArchiveNestedUnit.run(directory: directory) { runs += 1 }
            XCTAssertEqual(runs, 2)
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertEqual(lease.generation, 2)
        }
    }

    func testNestedUnitRefusesWhileTransactionUnresolved() throws {
        try withDirectory { directory in
            _ = try makeTransaction(in: directory)
            var ran = false
            XCTAssertThrowsError(try SharedArchiveNestedUnit.run(directory: directory) { ran = true }) {
                XCTAssertEqual($0 as? SharedArchiveAdmissionError, .unresolvedRecoveryTransaction)
            }
            XCTAssertFalse(ran)
            // Nothing committed: the generation chain did not advance.
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertEqual(lease.generation, 0)
        }
    }

    func testNestedUnitThrowingWorkCommitsNothing() throws {
        try withDirectory { directory in
            struct WorkFailed: Error {}
            XCTAssertThrowsError(try SharedArchiveNestedUnit.run(directory: directory) { throw WorkFailed() })
            let lease = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { lease.release() }
            XCTAssertEqual(lease.generation, 0)
        }
    }

    // MARK: One-call extension composition

    func testExtensionBoundaryComposesAndFailsClosedWhileResetPending() throws {
        // Never use or remove the host's real App Group control directory in tests.
        try withDirectory { directory in
            let gate = try SharedFileWriterGate(
                directory: directory,
                resetPending: { try SharedResetControl.exists(directory: directory) },
                archive: SharedArchiveNestedLeaseBoundary { work in
                    try SharedArchiveNestedUnit.run(directory: directory, work)
                })
            var ran = false
            try gate.makeBoundary().withEffect { ran = true }
            XCTAssertTrue(ran)
            try Data("control".utf8).write(to: directory.appendingPathComponent(SharedResetControl.fileName))
            XCTAssertThrowsError(try gate.makeBoundary()) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .resetPending)
            }
        }
    }
}
