import XCTest
@testable import Ate

@MainActor
final class JournalArchiveFilesystemMediaTests: XCTestCase {
    enum Injected: Error { case failure }
    private func fixture() throws -> URL {
        // Resolve system temporary-directory aliases BEFORE entering strict no-symlink adapter.
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveMediaTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private let bytes = Data((0..<262_147).map { UInt8($0 % 256) })

    func testFullBytesPublishReadbackFinishAndUnrelatedFilePreserved() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let unrelated = dir.appendingPathComponent("unrelated.jpg")
        try Data([9]).write(to: unrelated)
        let media = try JournalArchiveFilesystemMedia(directory: dir)
        try media.stage(["photo.jpg": bytes, "empty.bin": Data()])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("photo.jpg").path))
        try media.publish(); try media.verify(); try media.finish()
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("photo.jpg")), bytes)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("empty.bin")), Data())
        XCTAssertEqual(try Data(contentsOf: unrelated), Data([9]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(),
                       ["empty.bin", "photo.jpg", "unrelated.jpg"])
    }

    func testExistingDestinationNeverOverwrittenOrRemoved() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("photo.jpg")
        try Data([7]).write(to: file)
        let media = try JournalArchiveFilesystemMedia(directory: dir)
        try media.stage(["photo.jpg": bytes])
        XCTAssertThrowsError(try media.publish())
        try media.rollback()
        XCTAssertEqual(try Data(contentsOf: file), Data([7]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["photo.jpg"])
    }

    func testDestinationSymlinkCannotOverwriteTarget() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("target.jpg")
        try Data([7]).write(to: target)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("photo.jpg"), withDestinationURL: target)
        let media = try JournalArchiveFilesystemMedia(directory: dir)
        try media.stage(["photo.jpg": bytes])
        XCTAssertThrowsError(try media.publish()); try media.rollback()
        XCTAssertEqual(try Data(contentsOf: target), Data([7]))
    }

    func testEachWritePublishReadbackFailureRollsBackOnlyOwnedFiles() throws {
        for point in [JournalArchiveFilesystemMedia.Boundary.beforeWrite, .afterWrite, .beforeLink, .afterLink, .beforeReadback] {
            let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
            let media = try JournalArchiveFilesystemMedia(directory: dir) { current, _ in
                if current == point { throw Injected.failure }
            }
            XCTAssertThrowsError(try {
                try media.stage(["a.jpg": self.bytes, "b.jpg": Data([2])])
                try media.publish(); try media.verify()
            }())
            try media.rollback()
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }

    func testReplacedOwnedDestinationIsNotDeletedAndRecoveryReceiptSurvives() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let media = try JournalArchiveFilesystemMedia(directory: dir)
        try media.stage(["photo.jpg": bytes]); try media.publish()
        let file = dir.appendingPathComponent("photo.jpg")
        try FileManager.default.removeItem(at: file)
        try Data([42]).write(to: file)
        XCTAssertThrowsError(try media.verify())
        XCTAssertThrowsError(try media.rollback())
        XCTAssertEqual(try Data(contentsOf: file), Data([42]))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".ate-restore-") })
    }

    func testUnsafeNamesAndSymlinkDirectoryRefused() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let media = try JournalArchiveFilesystemMedia(directory: dir)
        XCTAssertThrowsError(try media.stage(["../escape": bytes]))
        let alias = dir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dir)
        XCTAssertThrowsError(try JournalArchiveFilesystemMedia(directory: alias))
    }

    func testCleanupFailureIsVisibleAndRetryable() throws {
        let dir = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        var fail = true
        let media = try JournalArchiveFilesystemMedia(directory: dir) { point, _ in
            if point == .beforeRemove, fail { throw Injected.failure }
        }
        try media.stage(["photo.jpg": bytes]); try media.publish()
        XCTAssertThrowsError(try media.rollback())
        fail = false
        try media.rollback()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}

@MainActor
final class ArchiveMediaLeaseLossTests: XCTestCase {
    enum Lost: Error { case lease }
    func testLostLeaseBlocksRollbackAndPreservesPublishedBytes() throws {
        let dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ArchiveLeaseLoss-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        var held = true
        let adapter = try JournalArchiveFilesystemMedia(directory: dir,
            validateLease: { if !held { throw Lost.lease } })
        try adapter.stage(["photo.jpg": Data([1,2,3])]); try adapter.publish()
        held = false
        XCTAssertThrowsError(try adapter.rollback())
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("photo.jpg")), Data([1,2,3]))
        held = true
        try adapter.rollback()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}
