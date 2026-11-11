import XCTest
@testable import Ate

final class JournalLocalOwnerIdentityTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    func testIdentitySurvivesRepeatedOpenWithoutChangingBytes() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try JournalLocalOwnerIdentity.loadOrCreate(in: directory)
        let file = directory.appendingPathComponent(JournalLocalOwnerIdentity.filename)
        let bytes = try Data(contentsOf: file)
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(try JournalLocalOwnerIdentity.loadOrCreate(in: directory), first)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testMalformedExistingIdentityIsPreservedNotReplaced() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(JournalLocalOwnerIdentity.filename)
        let bytes = Data("do not replace me".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try JournalLocalOwnerIdentity.loadOrCreate(in: directory))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testSymbolicLinkIdentityIsRefusedWithoutTouchingTarget() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        let bytes = Data(UUID().uuidString.utf8)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(JournalLocalOwnerIdentity.filename),
                                                   withDestinationURL: target)
        XCTAssertThrowsError(try JournalLocalOwnerIdentity.loadOrCreate(in: directory))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }
}
