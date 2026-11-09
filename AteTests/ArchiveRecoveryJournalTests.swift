import XCTest
@testable import Ate

@MainActor
final class ArchiveRecoveryJournalTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveRecoveryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func record(_ lease: POSIXArchiveWriterLease) -> ArchiveRecoveryRecord {
        ArchiveRecoveryRecord(version: 1, transactionID: UUID(), ownerIdentity: "fixture-owner",
            storeGeneration: lease.generation,
            images: [ArchiveRecoveryImage(component: "fixture", before: nil, after: Data([1]))],
            journalAndMediaRecovery: Data([42]))
    }

    func testNonblockingContentionReleaseAndGenerationPersistsOnReacquire() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try POSIXArchiveWriterLease(directory: dir)
        XCTAssertThrowsError(try POSIXArchiveWriterLease(directory: dir))
        try first.commitGeneration(1); first.release()
        let second = try POSIXArchiveWriterLease(directory: dir)
        defer { second.release() }
        XCTAssertEqual(second.generation, 1)
        XCTAssertThrowsError(try second.commitGeneration(3))
        try second.commitGeneration(2)
        XCTAssertThrowsError(try first.validate())
    }

    func testImmutablePreparedImagePhaseOrderAndRetirement() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease)
        try journal.prepare(expected)
        XCTAssertEqual(try journal.read(expected.transactionID), expected)
        XCTAssertEqual(try journal.phase(expected.transactionID), .prepared)
        XCTAssertThrowsError(try journal.transition(expected.transactionID, to: .committed))
        try journal.transition(expected.transactionID, to: .applying)
        try journal.transition(expected.transactionID, to: .committed)
        XCTAssertThrowsError(try journal.transition(expected.transactionID, to: .rolledBack))
        try journal.retire(expected.transactionID)
        XCTAssertTrue(try journal.transactions().isEmpty)
    }

    func testStartupCompensatesWithoutCommitAndVerifiesExplicitAbsentBeforeImage() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease)
        try journal.prepare(expected); try journal.transition(expected.transactionID, to: .applying)
        var actual: Data? = Data([1]); var mediaUndone = false
        let executor = ArchiveStartupRecovery(journal: journal, handlers: [
            .init(component: "fixture", restoreBefore: { actual = $0 },
                  verifyBefore: { XCTAssertEqual(actual, $0) }, verifyAfter: { _ in XCTFail("must not commit") })
        ], journalMedia: .init(compensate: { _ in mediaUndone = true }, verifyBefore: { _ in },
                              verifyAfter: { _ in XCTFail("must not commit") }, finishCommitted: { _ in XCTFail("must not commit") }))
        try executor.run(ownerIdentity: "fixture-owner")
        XCTAssertNil(actual); XCTAssertTrue(mediaUndone)
        XCTAssertTrue(try journal.transactions().isEmpty)
    }

    func testOwnerMismatchLeavesEvidenceAndRunsNoHandler() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease); try journal.prepare(expected)
        let executor = ArchiveStartupRecovery(journal: journal, handlers: [],
            journalMedia: .init(compensate: { _ in XCTFail("no undo") }, verifyBefore: { _ in },
                                verifyAfter: { _ in }, finishCommitted: { _ in }))
        XCTAssertThrowsError(try executor.run(ownerIdentity: "other-owner"))
        XCTAssertEqual(try journal.transactions(), [expected.transactionID])
    }

    func testTornOrTamperedPreparedRecordBlocksRatherThanGuessing() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease); try journal.prepare(expected)
        try Data([0]).write(to: dir.appendingPathComponent("txn-" + expected.transactionID.uuidString).appendingPathComponent("record.json"))
        XCTAssertThrowsError(try journal.read(expected.transactionID))
        XCTAssertFalse(try journal.transactions().isEmpty)
    }
    func testUnrelatedSharedDirectoryFilesDoNotBecomeTransactions() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0]).write(to: dir.appendingPathComponent(".DS_Store"))
        try Data([0]).write(to: dir.appendingPathComponent("unrelated.json"))
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        XCTAssertTrue(try journal.transactions().isEmpty)
        try journal.prepare(record(lease))
        XCTAssertEqual(try journal.transactions().count, 1)
    }

    func testDurableCompensatingIntentSupersedesCommitAndResumesUndo() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease); try journal.prepare(expected)
        try journal.transition(expected.transactionID, to: .applying)
        try journal.transition(expected.transactionID, to: .committed)
        // Engine must do this BEFORE its first undo when media.finish throws.
        try journal.transition(expected.transactionID, to: .compensating)
        XCTAssertEqual(try journal.phase(expected.transactionID), .compensating)
        var undoRan = false
        let executor = ArchiveStartupRecovery(journal: journal, handlers: [
            .init(component: "fixture", restoreBefore: { _ in undoRan = true },
                  verifyBefore: { _ in }, verifyAfter: { _ in XCTFail("undo intent wins") })
        ], journalMedia: .init(compensate: { _ in }, verifyBefore: { _ in },
                              verifyAfter: { _ in XCTFail("undo intent wins") }, finishCommitted: { _ in XCTFail("undo intent wins") }))
        try executor.run(ownerIdentity: "fixture-owner")
        XCTAssertTrue(undoRan); XCTAssertTrue(try journal.transactions().isEmpty)
    }

    func testCommittedHistorySurvivesCompensatingAndRolledBackPriority() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease); try journal.prepare(expected)
        XCTAssertFalse(try journal.history(expected.transactionID).hasCommittedMarker)
        try journal.transition(expected.transactionID, to: .applying)
        try journal.transition(expected.transactionID, to: .committed)
        try journal.transition(expected.transactionID, to: .compensating)
        XCTAssertEqual(try journal.history(expected.transactionID).phase, .compensating)
        XCTAssertTrue(try journal.history(expected.transactionID).hasCommittedMarker)
        try journal.transition(expected.transactionID, to: .rolledBack)
        XCTAssertEqual(try journal.history(expected.transactionID).phase, .rolledBack)
        XCTAssertTrue(try journal.history(expected.transactionID).hasCommittedMarker)
    }

    func testStartupGenerationMatrixUsesHistoricalCommitRatherThanWinningPhase() throws {
        // committed and post-commit undo allow g/g+1. No-commit undo allows g only.
        for committed in [false, true] {
            for undo in [false, true] {
                for advance in 0...2 {
                    let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
                    let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
                    let journal = DiskArchiveRecoveryJournal(lease: lease)
                    let expected = record(lease); try journal.prepare(expected)
                    try journal.transition(expected.transactionID, to: .applying)
                    if committed { try journal.transition(expected.transactionID, to: .committed) }
                    if undo { try journal.transition(expected.transactionID, to: .compensating) }
                    for _ in 0..<advance { try lease.commitGeneration(lease.generation + 1) }
                    var handlerCalls = 0
                    let executor = ArchiveStartupRecovery(journal: journal, handlers: [
                        .init(component: "fixture", restoreBefore: { _ in handlerCalls += 1 },
                              verifyBefore: { _ in handlerCalls += 1 }, verifyAfter: { _ in handlerCalls += 1 })
                    ], journalMedia: .init(compensate: { _ in handlerCalls += 1 }, verifyBefore: { _ in },
                                          verifyAfter: { _ in }, finishCommitted: { _ in handlerCalls += 1 }))
                    let accepted = advance == 0 || (committed && advance == 1)
                    if accepted {
                        try executor.run(ownerIdentity: "fixture-owner")
                        XCTAssertGreaterThan(handlerCalls, 0)
                        XCTAssertTrue(try journal.transactions().isEmpty)
                    } else {
                        XCTAssertThrowsError(try executor.run(ownerIdentity: "fixture-owner"))
                        XCTAssertEqual(handlerCalls, 0)
                        XCTAssertEqual(try journal.transactions(), [expected.transactionID])
                    }
                }
            }
        }
    }

    func testMalformedHistoricalCommitCannotAuthorizeAdvancedGeneration() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = try POSIXArchiveWriterLease(directory: dir); defer { lease.release() }
        let journal = DiskArchiveRecoveryJournal(lease: lease)
        let expected = record(lease); try journal.prepare(expected)
        try journal.transition(expected.transactionID, to: .applying)
        try journal.transition(expected.transactionID, to: .committed)
        try journal.transition(expected.transactionID, to: .compensating)
        try lease.commitGeneration(1)
        try Data("wrong identity".utf8).write(to: dir.appendingPathComponent("txn-" + expected.transactionID.uuidString)
            .appendingPathComponent(ArchiveRecoveryPhase.committed.rawValue))
        let executor = ArchiveStartupRecovery(journal: journal, handlers: [],
            journalMedia: .init(compensate: { _ in XCTFail("no undo") }, verifyBefore: { _ in },
                                verifyAfter: { _ in XCTFail("no verify") }, finishCommitted: { _ in XCTFail("no cleanup") }))
        XCTAssertThrowsError(try journal.history(expected.transactionID))
        XCTAssertThrowsError(try executor.run(ownerIdentity: "fixture-owner"))
        XCTAssertEqual(try journal.transactions(), [expected.transactionID])
    }

}
