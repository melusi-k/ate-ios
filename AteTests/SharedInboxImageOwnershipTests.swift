import XCTest
@testable import Ate

@MainActor
final class SharedInboxImageOwnershipTests: XCTestCase {
    func testActualImageProviderCompletionAfterResetCannotCreateLateBytes() async throws {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let directory = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = directory.appendingPathComponent("control", isDirectory: true)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: false)
        let app = try AccountWriterGate(directory: control, resetControlExists: { false })
        let shared = try SharedFileWriterGate(directory: control, resetPending: { false },
            archive: SharedArchiveNestedLeaseBoundary { work in try SharedArchiveNestedUnit.run(directory: control, work) })
        let original = try shared.makeBoundary()
        let inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        let started = expectation(description: "provider suspended")
        var release: CheckedContinuation<Data?, Never>?
        let task = Task { @MainActor in
            await SharedInbox.saveImage(boundary: original, directory: inbox) {
                await withCheckedContinuation { release = $0; started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        try app.acquireResetGate()
        try app.validateResetGate()
        app.releaseResetGate()
        release?.resume(returning: Data("late personal image".utf8)); release = nil
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path), "Not even the old personal directory may be created")
        // A genuinely new invocation may capture the new epoch and save normally.
        let replacement = try shared.makeBoundary()
        let name = await SharedInbox.saveImage(boundary: replacement, directory: inbox) { Data("fresh image".utf8) }
        XCTAssertNotNil(name)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path).count, 1)
    }
}
