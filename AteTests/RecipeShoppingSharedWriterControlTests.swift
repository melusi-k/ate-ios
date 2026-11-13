import XCTest
@testable import Ate

/// Native UNRUN. Real app gate/shared gate, shared epoch and retained redo files.
@MainActor
final class RecipeShoppingSharedWriterControlTests: XCTestCase {
    private func fixture(_ work: (URL, AccountWriterGate, UUID, RecipeShoppingSharedWriterControl) throws -> Void) throws {
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let root = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(RecipeShoppingSharedWriterControl.commitDirectoryName), withIntermediateDirectories: false)
        let gate = try AccountWriterGate(directory: root, resetControlExists: { false })
        let lease = try gate.captureWriter()
        try work(root, gate, lease, RecipeShoppingSharedWriterControl(directory: root))
    }
    func testExtensionCannotWriteBeforeReadinessAndDoesNotCreateMarker() throws {
        try fixture { root, gate, lease, control in
            let boundary = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
            var ran = false
            XCTAssertThrowsError(try boundary.withEffect { ran = true })
            XCTAssertFalse(ran)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recipe-shopping-ready-v1").path))
            try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) }
            try boundary.withEffect { ran = true }
            XCTAssertTrue(ran)
        }
    }
    func testNewEpochExtensionRefusesOldReadyAndOldCapturedBoundaryCannotRevive() throws {
        try fixture { root, gate, lease, control in
            try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) }
            let old = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
            try old.withEffect {}
            try gate.invalidateWriters()
            let new = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
            XCTAssertThrowsError(try old.withEffect {})
            XCTAssertThrowsError(try new.withEffect {})
            let next = try gate.captureWriter()
            try gate.withWriterEffect(next) { try control.publishReady(epoch: next) }
            try new.withEffect {}
            XCTAssertThrowsError(try old.withEffect {})
        }
    }
    func testAnyPendingIntentOrMetadataTempBlocksEffectsWithoutDeletingEvidence() throws {
        try fixture { root, gate, lease, control in
            try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) }
            let boundary = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
            for name in ["pending-v1.json", "pending-v1.json.tmp", "metadata-v1.json.tmp"] {
                let url = control.commitDirectory.appendingPathComponent(name), evidence = Data("unresolved".utf8)
                try evidence.write(to: url)
                XCTAssertThrowsError(try boundary.withEffect { XCTFail("redo bypassed") })
                XCTAssertThrowsError(try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) })
                XCTAssertEqual(try Data(contentsOf: url), evidence)
                try FileManager.default.removeItem(at: url) // fixture teardown only, not production recovery
            }
            try boundary.withEffect {}
        }
    }
    func testCorruptReadyOrTempNeverRepairsAndResetEpochInvalidates() throws {
        try fixture { root, gate, lease, control in
            let marker = root.appendingPathComponent("recipe-shopping-ready-v1")
            let bad = Data("not-an-epoch".utf8); try bad.write(to: marker)
            let boundary = try RecipeShoppingSharedWriterControl.makeExtensionBoundary(directory: root)
            XCTAssertThrowsError(try boundary.withEffect {})
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) })
            XCTAssertEqual(try Data(contentsOf: marker), bad)
            try FileManager.default.removeItem(at: marker)
            try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) }
            let temp = marker.appendingPathExtension("tmp"); try bad.write(to: temp)
            XCTAssertThrowsError(try boundary.withEffect {})
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { try control.publishReady(epoch: lease) })
            XCTAssertEqual(try Data(contentsOf: temp), bad)
            try FileManager.default.removeItem(at: temp)
            try gate.acquireResetGate(); gate.releaseResetGate()
            XCTAssertThrowsError(try boundary.withEffect {})
        }
    }
}
