import XCTest
@testable import Ate

/// #245 slice B: the composed writer boundary (Shape A). The validator must NEVER
/// advance the archive generation - only real effects enter the archive's nested lease.
@MainActor
final class JournalWriterBoundaryCompositionTests: XCTestCase {
    private func fixture(_ run: (URL) throws -> Void) throws {
        // Canonical-directory rule: resolve symlinked temp ancestors AFTER creation
        // (same fixture rule as AccountWriterGateTests).
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let directory = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    func testValidationNeverAdvancesArchiveGeneration() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let archive = FakeNestedBoundary()
            let lease = try gate.captureWriter()
            let perform = JournalWriterBoundaryComposition.makePerform(gate: gate, writerLease: lease,
                                                                       archive: archive)
            try perform { }
            XCTAssertEqual(archive.commits, 1, "A real covered effect commits exactly one generation")

            let validate = JournalWriterBoundaryComposition.makeValidator(gate: gate, writerLease: lease,
                                                                          archive: archive)
            try validate()
            try validate()
            XCTAssertEqual(archive.commits, 1,
                           "Validation must never enter the archive boundary or commit a generation")
        }
    }

    func testValidationInsideAnActiveOuterLeaseDoesNotNestAGeneration() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let archive = FakeNestedBoundary()
            let lease = try gate.captureWriter()
            let perform = JournalWriterBoundaryComposition.makePerform(gate: gate, writerLease: lease,
                                                                       archive: archive)
            let validate = JournalWriterBoundaryComposition.makeValidator(gate: gate, writerLease: lease,
                                                                          archive: archive)
            try perform {
                // Per-component re-proof inside one larger composed effect (the wipe shape).
                try validate()
                try validate()
            }
            XCTAssertEqual(archive.commits, 1,
                           "Nested validation reuses the held lock and stamps no second generation")
        }
    }

    func testValidatorRejectsARotatedLease() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let archive = FakeNestedBoundary()
            let old = try gate.captureWriter()
            try gate.acquireResetGate()
            gate.releaseResetGate()
            let validate = JournalWriterBoundaryComposition.makeValidator(gate: gate, writerLease: old,
                                                                          archive: archive)
            XCTAssertThrowsError(try validate(), "A pre-reset lease is stale after a reset rotates the epoch")
            XCTAssertEqual(archive.commits, 0)
        }
    }

    func testPerformRunsEffectInsideBothBoundaries() throws {
        try fixture { directory in
            let gate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let archive = FakeNestedBoundary()
            let lease = try gate.captureWriter()
            let perform = JournalWriterBoundaryComposition.makePerform(gate: gate, writerLease: lease,
                                                                       archive: archive)
            var ran = false
            try perform { ran = true }
            XCTAssertTrue(ran)
            XCTAssertEqual(archive.commits, 1)
        }
    }
}

/// Stands in for A's ArchiveNestedGenerationBoundary: each covered unit is one
/// generation commit. Nonisolated like the boundary itself; the tests drive it from
/// MainActor.
private final class FakeNestedBoundary: ArchiveNestedLeaseBoundary {
    private(set) var commits = 0
    func withNestedLease<T>(_ work: () throws -> T) throws -> T {
        commits += 1
        return try work()
    }
}
