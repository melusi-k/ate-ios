import XCTest
@testable import Ate

final class SharedWriterRemountTests: XCTestCase {
    func testReplaceRequiresExactRetiredInstalledBoundaryAndOldCapturesRefuse() throws {
        SharedWriterBoundary.resetForTesting(); defer { SharedWriterBoundary.resetForTesting() }
        var oldEffects = 0, newEffects = 0
        let old = SharedWriterBoundary { effect in oldEffects += 1; try effect() }
        let next = SharedWriterBoundary { effect in newEffects += 1; try effect() }
        XCTAssertTrue(SharedWriterBoundary.install(old))
        let capturedBeforeAwait = SharedWriterBoundary.current
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(old, with: next))
        try old.withEffect {}
        try old.retire()
        XCTAssertTrue(SharedWriterBoundary.replaceRetired(old, with: next))
        XCTAssertThrowsError(try capturedBeforeAwait.withEffect { XCTFail("stale captured boundary ran") }) {
            XCTAssertEqual($0 as? SharedWriterBoundary.Failure, .retired)
        }
        try SharedWriterBoundary.current.withEffect {}
        XCTAssertEqual(oldEffects, 1); XCTAssertEqual(newEffects, 1)
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(old, with: next))
        XCTAssertFalse(SharedWriterBoundary.install(old))
    }
    func testRetirementFromInsideEffectRefusesThenRetirementIsPermanent() throws {
        let boundary = SharedWriterBoundary { try $0() }
        try boundary.withEffect {
            XCTAssertThrowsError(try boundary.retire()) {
                XCTAssertEqual($0 as? SharedWriterBoundary.Failure, .effectActive)
            }
            XCTAssertFalse(boundary.isRetired)
            try boundary.withEffect {}
        }
        try boundary.retire(); try boundary.retire()
        XCTAssertTrue(boundary.isRetired)
        XCTAssertThrowsError(try boundary.withEffect {})
    }
    func testUninstalledRetiredIdentityLegacyAndRetiredReplacementAreRejected() throws {
        SharedWriterBoundary.resetForTesting(); defer { SharedWriterBoundary.resetForTesting() }
        let first = SharedWriterBoundary { try $0() }, other = SharedWriterBoundary { try $0() }
        let next = SharedWriterBoundary { try $0() }
        XCTAssertTrue(SharedWriterBoundary.install(first))
        try other.retire()
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(other, with: next))
        try first.retire()
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(first, with: first))
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(first, with: .legacy))
        try next.retire()
        XCTAssertFalse(SharedWriterBoundary.replaceRetired(first, with: next))
        XCTAssertTrue(SharedWriterBoundary.current === first)
        XCTAssertThrowsError(try SharedWriterBoundary.current.withEffect {})
    }
}
