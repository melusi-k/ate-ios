import XCTest
@testable import Ate

@MainActor
final class SharedWriterGateTests: XCTestCase {
    private func fixture(_ run: (URL) throws -> Void) throws {
        // Same canonical-directory rule as AccountWriterGateTests: resolve the
        // fixture root AFTER creating it (/var -> /private/var symlink on Apple
        // hosts), production guards stay unchanged.
        let requested = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: false)
        let directory = requested.resolvingSymlinksInPath().standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    private func makeGate(_ directory: URL,
                          resetPending: @escaping () throws -> Bool = { false },
                          archive: SharedArchiveNestedLeaseBoundary = .none) throws -> SharedFileWriterGate {
        try SharedFileWriterGate(directory: directory, resetPending: resetPending, archive: archive)
    }

    private func gatedBoundary(archive: SharedArchiveNestedLeaseBoundary = .none,
                               _ run: (SharedWriterBoundary) throws -> Void) throws {
        try fixture { directory in
            try run(try makeGate(directory, archive: archive).makeBoundary())
        }
    }

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "shared-gate-test-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    private let refusing = SharedWriterBoundary { _ in throw SharedWriterBoundary.Failure.effectNotPerformed }

    // MARK: Boundary contract (mirrors FoodJournalWriterBoundary)

    func testBoundaryRunsEffectExactlyOnce() throws {
        var performs = 0
        let boundary = SharedWriterBoundary { effect in performs += 1; try effect() }
        var runs = 0
        let value = try boundary.withEffect { runs += 1; return 42 }
        XCTAssertEqual(value, 42)
        XCTAssertEqual(performs, 1)
        XCTAssertEqual(runs, 1)
    }

    func testBoundaryNestedEffectRunsUnderOuterWithoutSecondPerform() throws {
        var performs = 0
        let boundary = SharedWriterBoundary { effect in performs += 1; try effect() }
        try boundary.withEffect {
            try boundary.withEffect { }
        }
        XCTAssertEqual(performs, 1)
    }

    func testBoundaryRejectsRepeatedEffect() throws {
        let boundary = SharedWriterBoundary { effect in try effect(); try effect() }
        XCTAssertThrowsError(try boundary.withEffect { }) {
            XCTAssertEqual($0 as? SharedWriterBoundary.Failure, .repeatedEffect)
        }
    }

    func testBoundaryRejectsSkippedEffect() throws {
        let boundary = SharedWriterBoundary { _ in }
        XCTAssertThrowsError(try boundary.withEffect { }) {
            XCTAssertEqual($0 as? SharedWriterBoundary.Failure, .effectNotPerformed)
        }
    }

    func testLegacyBoundaryRunsDirectly() throws {
        var ran = false
        try SharedWriterBoundary.legacy.withEffect { ran = true }
        XCTAssertTrue(ran)
    }

    func testCurrentDefaultsToLegacyAndInstallIsOneWay() {
        SharedWriterBoundary.resetForTesting()
        defer { SharedWriterBoundary.resetForTesting() }
        XCTAssertTrue(SharedWriterBoundary.current === SharedWriterBoundary.legacy)
        let first = SharedWriterBoundary { try $0() }
        let second = SharedWriterBoundary { try $0() }
        XCTAssertTrue(SharedWriterBoundary.install(first))
        XCTAssertTrue(SharedWriterBoundary.current === first)
        XCTAssertFalse(SharedWriterBoundary.install(second))
        XCTAssertTrue(SharedWriterBoundary.current === first)
    }

    // MARK: App-process adapter

    func testAdapterRunsEffectsInsideTheAlreadyHeldOuterBoundary() throws {
        var outerPerforms = 0
        let outer = SharedWriterBoundary { effect in outerPerforms += 1; try effect() }
        let adapted = SharedWriterBoundary.adapting { work in try outer.withEffect(work) }
        var runs = 0
        try adapted.withEffect { runs += 1 }
        XCTAssertEqual(outerPerforms, 1)
        XCTAssertEqual(runs, 1)
    }

    func testAdapterNestsUnderAnActiveOuterEffectWithoutASecondGate() throws {
        var outerPerforms = 0
        let outer = SharedWriterBoundary { effect in outerPerforms += 1; try effect() }
        let adapted = SharedWriterBoundary.adapting { work in try outer.withEffect(work) }
        var innerRan = false
        try outer.withEffect {
            // Reached from inside a central effect: the adapter must nest via the
            // outer boundary's own reentrancy, not gate again.
            try adapted.withEffect { innerRan = true }
        }
        XCTAssertTrue(innerRan)
        XCTAssertEqual(outerPerforms, 1)
    }

    // MARK: Gate: mutual exclusion

    func testSecondInstanceOnSameDirectoryIsBusyWhileEffectHeld() throws {
        try fixture { directory in
            let first = try makeGate(directory)
            let second = try makeGate(directory)
            let lease = try first.captureEpoch()
            var inner = false
            try first.withWriterEffect(lease) {
                XCTAssertThrowsError(try second.withWriterEffect(lease) { inner = true }) {
                    XCTAssertEqual($0 as? SharedFileWriterGate.Error, .busy)
                }
            }
            XCTAssertFalse(inner)
            // Released afterwards: the second instance can proceed.
            try second.withWriterEffect(lease) { inner = true }
            XCTAssertTrue(inner)
        }
    }

    func testSameInstanceNestedEffectNeverTouchesTheOSLockAgain() throws {
        try fixture { directory in
            let gate = try makeGate(directory)
            let lease = try gate.captureEpoch()
            var depth = 0
            try gate.withWriterEffect(lease) {
                depth += 1
                try gate.withWriterEffect(lease) { depth += 1 }
            }
            XCTAssertEqual(depth, 2)
        }
    }

    func testNestedEffectRejectsAMismatchedLease() throws {
        try fixture { directory in
            let gate = try makeGate(directory)
            let lease = try gate.captureEpoch()
            try gate.withWriterEffect(lease) {
                XCTAssertThrowsError(try gate.withWriterEffect(UUID()) { }) {
                    XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
                }
            }
        }
    }

    func testGateRejectsSymlinkDirectory() throws {
        try fixture { directory in
            let real = directory.appendingPathComponent("real")
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
            let link = directory.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            XCTAssertThrowsError(try makeGate(link)) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .unsafePath)
            }
        }
    }

    // MARK: Gate: reset control

    func testCaptureAndEffectRefuseWhileResetControlExists() throws {
        try fixture { directory in
            var pending = true
            let gate = try makeGate(directory, resetPending: { pending })
            XCTAssertThrowsError(try gate.captureEpoch()) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .resetPending)
            }
            pending = false
            let lease = try gate.captureEpoch()
            pending = true
            var ran = false
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { ran = true }) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .resetPending)
            }
            XCTAssertFalse(ran)
            XCTAssertThrowsError(try gate.validate(lease)) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .resetPending)
            }
        }
    }

    func testResetEpochAdvanceInvalidatesPreResetExtensionLease() throws {
        try fixture { directory in
            // Simulates the shared control directory after the account gate's
            // reset advanced the writer epoch: an extension write captured before
            // the reset must be rejected, never recreating erased data. Uses the
            // real app-side AccountWriterGate to prove the two gates read the
            // same epoch file and format.
            let extensionGate = try makeGate(directory)
            let preResetLease = try extensionGate.captureEpoch()
            let accountGate = try AccountWriterGate(directory: directory, resetControlExists: { false })
            try accountGate.invalidateWriters()
            var ran = false
            XCTAssertThrowsError(try extensionGate.withWriterEffect(preResetLease) { ran = true }) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
            }
            XCTAssertFalse(ran)
            XCTAssertThrowsError(try extensionGate.validate(preResetLease)) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
            }
            // A fresh capture follows the post-reset epoch and writes again.
            let postResetLease = try extensionGate.captureEpoch()
            XCTAssertNotEqual(postResetLease, preResetLease)
            try extensionGate.withWriterEffect(postResetLease) { ran = true }
            XCTAssertTrue(ran)
        }
    }

    // MARK: Gate: epoch

    func testEpochIsSharedAcrossInstancesAndSurvivesRecapture() throws {
        try fixture { directory in
            let first = try makeGate(directory)
            let second = try makeGate(directory)
            let epoch = try first.captureEpoch()
            XCTAssertEqual(try second.captureEpoch(), epoch)
            XCTAssertEqual(try first.captureEpoch(), epoch)
            XCTAssertNoThrow(try second.validate(epoch))
        }
    }

    func testValidateRejectsForeignEpoch() throws {
        try fixture { directory in
            let gate = try makeGate(directory)
            _ = try gate.captureEpoch()
            XCTAssertThrowsError(try gate.validate(UUID())) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
            }
        }
    }

    func testCorruptEpochIsNeverSilentlyRepaired() throws {
        try fixture { directory in
            let file = directory.appendingPathComponent(SharedWriterControl.epochFileName)
            try Data("broken".utf8).write(to: file)
            let gate = try makeGate(directory)
            XCTAssertThrowsError(try gate.captureEpoch()) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .corruptEpoch)
            }
            // The corrupt bytes are still there: no fresh epoch replaced them.
            XCTAssertEqual(String(data: try Data(contentsOf: file), encoding: .utf8), "broken")
        }
    }

    func testAppOnlyModeIsExplicitAndProcessLocal() throws {
        let gate = SharedFileWriterGate.appOnly
        XCTAssertEqual(gate.mode, .appOnly)
        let lease = try gate.captureEpoch()
        var ran = false
        try gate.withWriterEffect(lease) { ran = true }
        XCTAssertTrue(ran)
        XCTAssertNoThrow(try gate.validate(lease))
        XCTAssertThrowsError(try gate.validate(UUID())) {
            XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
        }
        XCTAssertThrowsError(try gate.withWriterEffect(UUID()) { }) {
            XCTAssertEqual($0 as? SharedFileWriterGate.Error, .staleLease)
        }
        // The explicit app-only boundary runs effects with no shared container.
        var boundaryRan = false
        try SharedFileWriterGate.appOnly.makeBoundary().withEffect { boundaryRan = true }
        XCTAssertTrue(boundaryRan)
    }

    // MARK: Gate: archive nested lease

    private enum TestError: Swift.Error { case unresolvedArchive }

    func testEffectRunsInsideArchiveLeaseAndAdvancesOncePerCommittedUnit() throws {
        try fixture { directory in
            var advances = 0
            let archive = SharedArchiveNestedLeaseBoundary { work in try work(); advances += 1 }
            let gate = try makeGate(directory, archive: archive)
            let lease = try gate.captureEpoch()
            try gate.withWriterEffect(lease) { }
            try gate.withWriterEffect(lease) { }
            XCTAssertEqual(advances, 2)
            // A throwing unit commits nothing: no generation advance.
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { throw TestError.unresolvedArchive })
            XCTAssertEqual(advances, 2)
        }
    }

    func testDirectSameLeaseNestingCommitsOneRealArchiveGeneration() throws {
        try fixture { directory in
            let archive = SharedArchiveNestedLeaseBoundary { work in
                try SharedArchiveNestedUnit.run(directory: directory, work)
            }
            let gate = try makeGate(directory, archive: archive)
            let epoch = try gate.captureEpoch()
            var innerRan = false
            try gate.withWriterEffect(epoch) {
                try gate.withWriterEffect(epoch) { innerRan = true }
                let inspection = try POSIXArchiveWriterLease(nestedDirectory: directory)
                defer { inspection.release() }
                XCTAssertEqual(inspection.generation, 0, "Inner work must not commit before outer completion")
            }
            XCTAssertTrue(innerRan)
            let inspection = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { inspection.release() }
            XCTAssertEqual(inspection.generation, 1, "Exactly one real durable generation per committed unit")
        }
    }

    func testDirectSameLeaseInnerSuccessThenOuterThrowCommitsZeroGenerations() throws {
        try fixture { directory in
            let archive = SharedArchiveNestedLeaseBoundary { work in
                try SharedArchiveNestedUnit.run(directory: directory, work)
            }
            let gate = try makeGate(directory, archive: archive)
            let epoch = try gate.captureEpoch()
            var innerRan = false
            XCTAssertThrowsError(try gate.withWriterEffect(epoch) {
                try gate.withWriterEffect(epoch) { innerRan = true }
                throw TestError.unresolvedArchive
            })
            XCTAssertTrue(innerRan)
            let inspection = try POSIXArchiveWriterLease(nestedDirectory: directory)
            defer { inspection.release() }
            XCTAssertEqual(inspection.generation, 0, "No generation may survive a failed outer unit")
        }
    }

    func testUnresolvedArchiveRefusesBeforeTheEffectRuns() throws {
        try fixture { directory in
            let archive = SharedArchiveNestedLeaseBoundary { _ in throw TestError.unresolvedArchive }
            let gate = try makeGate(directory, archive: archive)
            let lease = try gate.captureEpoch()
            var ran = false
            XCTAssertThrowsError(try gate.withWriterEffect(lease) { ran = true }) {
                XCTAssertEqual($0 as? TestError, .unresolvedArchive)
            }
            XCTAssertFalse(ran)
        }
    }

    func testValidationNeverAdvancesTheArchiveGeneration() throws {
        try fixture { directory in
            var archiveRuns = 0
            let archive = SharedArchiveNestedLeaseBoundary { work in archiveRuns += 1; try work() }
            let gate = try makeGate(directory, archive: archive)
            let lease = try gate.captureEpoch()
            try gate.validate(lease)
            try gate.validate(lease)
            XCTAssertEqual(archiveRuns, 0)
        }
    }

    func testBoundaryFromGateCarriesResetEpochAndArchiveChecks() throws {
        try fixture { directory in
            var pending = false
            var advances = 0
            let archive = SharedArchiveNestedLeaseBoundary { work in try work(); advances += 1 }
            let gate = try makeGate(directory, resetPending: { pending }, archive: archive)
            let boundary = try gate.makeBoundary()
            var ran = 0
            try boundary.withEffect { ran += 1 }
            XCTAssertEqual(ran, 1)
            XCTAssertEqual(advances, 1)
            pending = true
            XCTAssertThrowsError(try boundary.withEffect { ran += 1 }) {
                XCTAssertEqual($0 as? SharedFileWriterGate.Error, .resetPending)
            }
            XCTAssertEqual(ran, 1)
            XCTAssertEqual(advances, 1)
        }
    }

    // MARK: Composition

    func testControlDirectoryFollowsTheResolvedGroup() throws {
        try fixture { isolatedContainer in
            let resolution = AppGroupResolver.Resolution(id: "group.test.isolated", source: "test", available: true)
            var requestedID: String?
            let directory = try SharedWriterGateComposition.controlDirectory(resolution: resolution,
                containerURL: { id in requestedID = id; return isolatedContainer })
            XCTAssertEqual(requestedID, resolution.id)
            XCTAssertEqual(directory, isolatedContainer.appendingPathComponent(SharedWriterControl.directoryName,
                                                                               isDirectory: true))
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            // Only fixture() removes its unique temporary root. Never resolve or
            // remove the host app's real AteStateControl directory in this test.
        }
    }

    func testInjectedMissingContainerDoesNotFallBackToTheRealGroup() {
        let resolution = AppGroupResolver.Resolution(id: "group.test.isolated", source: "test", available: true)
        XCTAssertThrowsError(try SharedWriterGateComposition.controlDirectory(resolution: resolution,
                                                                               containerURL: { _ in nil }))
    }

    func testControlDirectoryFailsClosedForUnavailableResolution() {
        let missing = AppGroupResolver.Resolution(id: "group.test.absent", source: "test", available: false)
        XCTAssertThrowsError(try SharedWriterGateComposition.controlDirectory(resolution: missing)) {
            XCTAssertEqual($0 as? SharedWriterGateComposition.ResolutionError, .appGroupUnavailable)
        }
    }

    // MARK: Wired writers through injected boundaries

    func testGatedPushAndPopKeepFIFOThroughBoundary() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        try gatedBoundary { boundary in
            for i in 0..<3 { XCTAssertTrue(SharedInbox.push(.init(url: "https://x.test/\(i)"), d, boundary: boundary)) }
            XCTAssertEqual(SharedInbox.pop(d, boundary: boundary)?.url, "https://x.test/0")
            XCTAssertEqual(SharedInbox.load(d).compactMap(\.url), ["https://x.test/1", "https://x.test/2"])
        }
    }

    func testRefusedBoundaryQueuesNothingAndDrainsNothing() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(SharedInbox.push(.init(url: "https://x.test/1"), d, boundary: refusing))
        XCTAssertTrue(SharedInbox.load(d).isEmpty)
        WidgetInbox.setDone("a", true, d, boundary: .legacy)
        XCTAssertEqual(WidgetInbox.pendingShopping(d), ["a": true])
        let refused = WidgetInbox.drain(d, boundary: refusing)
        XCTAssertTrue(refused.shopping.isEmpty)
        // The refused drain cleared nothing: the entry is still queued.
        XCTAssertEqual(WidgetInbox.pendingShopping(d), ["a": true])
    }

    func testWidgetInboxRoundTripThroughRealGate() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        try gatedBoundary { boundary in
            XCTAssertTrue(WidgetInbox.setDone("milk", true, d, boundary: boundary))
            XCTAssertTrue(WidgetInbox.addItem("  eggs  ", d, boundary: boundary))
            XCTAssertTrue(WidgetInbox.openLater(URL(string: "ate://shopping")!, d, boundary: boundary))
            let q = WidgetInbox.drain(d, boundary: boundary)
            XCTAssertEqual(q.shopping, ["milk": true])
            XCTAssertEqual(q.adds, ["eggs"])
            XCTAssertEqual(q.url, URL(string: "ate://shopping"))
            XCTAssertTrue(WidgetInbox.pendingShopping(d).isEmpty)
        }
    }

    func testTimerSnapshotSaveReportsRefusal() throws {
        let original = TimerSnapshot.load()
        defer { TimerSnapshot.save(original, boundary: .legacy) }
        XCTAssertFalse(TimerSnapshot.save([], boundary: refusing))
        XCTAssertTrue(TimerSnapshot.save([], boundary: .legacy))
        XCTAssertEqual(TimerSnapshot.load(), [])
    }

    func testPublisherCommitsSaveAndCacheAtomicallyAndSkipsReloadOnRefusal() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        var publisher = WidgetSnapshotPublisher()
        let snap = WidgetSnapshot(recipeCount: 3)
        var reloaded: [[String]] = []
        XCTAssertTrue(publisher.publish(snap, defaults: d, boundary: .legacy, reload: { reloaded.append($0) }))
        XCTAssertEqual(WidgetSnapshot.load(d)?.recipeCount, 3)
        XCTAssertEqual(reloaded.count, 1)
        var newer = WidgetSnapshot(recipeCount: 4)
        // recipeCount alone is metadata, not a timeline dependency. Exercise a
        // real displayed change so an ordinary retry is supposed to publish.
        newer.shopping = [.init(id: "milk", name: "Milk", done: false)]
        XCTAssertFalse(publisher.publish(newer, force: true, defaults: d, boundary: refusing, reload: { reloaded.append($0) }))
        // Nothing committed: the persisted snapshot and the reloads are unchanged.
        XCTAssertEqual(WidgetSnapshot.load(d)?.recipeCount, 3)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(WidgetSnapshot.load(d)?.shopping, [])
        // The publisher did not mark the refused value as published: a later retry
        // with a working boundary still commits and reloads.
        XCTAssertTrue(publisher.publish(newer, defaults: d, boundary: .legacy, reload: { reloaded.append($0) }))
        XCTAssertEqual(WidgetSnapshot.load(d)?.recipeCount, 4)
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(WidgetSnapshot.load(d)?.shopping, newer.shopping)
        XCTAssertEqual(Set(reloaded.last ?? []), Set([WidgetKinds.shopping, WidgetKinds.shoppingInline]))
    }

    func testPublisherMetadataOnlyChangeDoesNotRequestTimelineReload() throws {
        let (d, suite) = try defaults()
        defer { d.removePersistentDomain(forName: suite) }
        var publisher = WidgetSnapshotPublisher()
        var reloads = 0
        let first = WidgetSnapshot(recipeCount: 3)
        XCTAssertTrue(publisher.publish(first, defaults: d, boundary: .legacy, reload: { _ in reloads += 1 }))
        var metadataOnly = first
        metadataOnly.recipeCount = 4
        XCTAssertFalse(publisher.publish(metadataOnly, defaults: d, boundary: .legacy, reload: { _ in reloads += 1 }))
        XCTAssertEqual(WidgetSnapshot.load(d), first)
        XCTAssertEqual(reloads, 1, "No displayed timeline input changed")
    }
}

extension SharedWriterGateTests {
    func testAccountConflictMarkerBlocksExtensionOldAndFreshLeases() throws {
        try fixture { directory in
            let app = try AccountWriterGate(directory: directory, resetControlExists: { false })
            let ext = try makeGate(directory)
            let old = try ext.captureEpoch()
            try app.blockWritersForGenerationConflict()
            XCTAssertThrowsError(try ext.validate(old))
            XCTAssertThrowsError(try ext.withWriterEffect(old) { XCTFail("extension wrote during generation conflict") })
            XCTAssertThrowsError(try ext.captureEpoch())
            XCTAssertThrowsError(try ext.makeBoundary())
            let restarted = try makeGate(directory)
            XCTAssertThrowsError(try restarted.captureEpoch())
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(SharedWriterControl.generationBlockFileName).path))
        }
    }

    func testExtensionNeverIgnoresCorruptOrSymlinkConflictEntry() throws {
        try fixture { directory in
            let ext = try makeGate(directory)
            let old = try ext.captureEpoch()
            let marker = directory.appendingPathComponent(SharedWriterControl.generationBlockFileName)
            try Data("not a UUID".utf8).write(to: marker)
            XCTAssertThrowsError(try ext.captureEpoch())
            XCTAssertThrowsError(try ext.withWriterEffect(old) { XCTFail("corrupt marker accepted") })
            try FileManager.default.removeItem(at: marker)
            try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: directory.appendingPathComponent("absent"))
            XCTAssertThrowsError(try ext.validate(old))
            XCTAssertThrowsError(try ext.captureEpoch())
        }
    }
}
