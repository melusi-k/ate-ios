import XCTest
@testable import Ate

@MainActor
final class FileResetControlPersistenceTests: XCTestCase {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
    func testExactBytesSurviveFreshReaderAndRetirement() throws {
        try fixture { directory in
            let control = FileResetControlPersistence(directory: directory)
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { try control.read() != nil })
            try gate.acquireResetGate(); defer { gate.releaseResetGate() }
            let data = Data("{\"fixture\":true}".utf8)
            try control.write(data)
            XCTAssertEqual(try FileResetControlPersistence(directory: directory).read(), data)
            try control.remove()
            XCTAssertNil(try control.read())
        }
    }
    func testMissingParentAndDanglingControlAreNotAbsent() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try FileResetControlPersistence(directory: missing).read())
        try fixture { directory in
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("reset-control-v1.json"),
                withDestinationURL: directory.appendingPathComponent("missing"))
            XCTAssertThrowsError(try FileResetControlPersistence(directory: directory).read())
        }
    }
}
