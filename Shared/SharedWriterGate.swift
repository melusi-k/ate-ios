import Foundation
import Darwin

@_silgen_name("flock")
private func shared_writer_flock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Well-known names of the shared cross-process writer control files (#245).
/// The app-side account writer gate (Ate/Store/AccountWriterGate.swift) uses the
/// same lock and epoch file names, so pointing both gates at one control directory
/// makes ordinary effects, extension writes and reset attempts mutually exclusive
/// by the OS, with exactly one flocked file.
enum SharedWriterControl {
    /// Control directory inside the resolved App Group container.
    static let directoryName = "AteStateControl"
    static let lockFileName = "writer-gate-v1.lock"
    static let epochFileName = "writer-epoch-v1"
}

/// Synchronous effect boundary for the shared App Group writers compiled into the
/// app, the widget extension and the share extension. Same contract as the central
/// FoodJournalWriterBoundary: the callback runs exactly once, synchronously, and
/// never suspends or escapes. `.legacy` runs effects directly, so nothing changes
/// while activation is off; canonical production startup installs the real
/// boundary in every process before ordinary use (see SharedWriterGateComposition).
final class SharedWriterBoundary {
    enum Failure: Error { case effectNotPerformed, repeatedEffect }
    private let lock = NSRecursiveLock()
    private var active = false
    private let perform: (() throws -> Void) throws -> Void

    init(perform: @escaping (() throws -> Void) throws -> Void) {
        self.perform = perform
    }

    /// Existing call sites and test graphs only.
    static let legacy = SharedWriterBoundary { try $0() }

    /// App-process adapter: shared writers run INSIDE the central writer boundary
    /// the app already holds (account gate OUTER per the agreed lock order),
    /// instead of flocking the same control file again, which would self-conflict.
    /// Only extension processes use the standalone SharedFileWriterGate-backed
    /// boundary. Pass the central boundary's effect runner closure-shaped, e.g.
    /// `{ work in try centralBoundary.withEffect(work) }`, so Shared/ never names
    /// app-target types. The central boundary's own reentrancy lets a shared
    /// writer reached from inside a central effect nest without a second gate.
    static func adapting(_ outerPerform: @escaping (() throws -> Void) throws -> Void) -> SharedWriterBoundary {
        SharedWriterBoundary(perform: outerPerform)
    }

    private static let installLock = NSRecursiveLock()
    private static var installed: SharedWriterBoundary?

    /// The boundary shared writers use by default. Read at every call site, so a
    /// boundary installed during startup applies to writers reached afterwards.
    static var current: SharedWriterBoundary {
        installLock.lock()
        defer { installLock.unlock() }
        return installed ?? .legacy
    }

    /// One-way install of the production boundary. Returns false and changes
    /// nothing when a non-legacy boundary is already installed.
    @discardableResult
    static func install(_ boundary: SharedWriterBoundary) -> Bool {
        installLock.lock()
        defer { installLock.unlock() }
        guard installed == nil else { return false }
        installed = boundary
        return true
    }

    /// Test-only reset; production code must never call this.
    static func resetForTesting() {
        installLock.lock()
        defer { installLock.unlock() }
        installed = nil
    }

    func withEffect<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if active { return try work() }
        var result: T?
        var performed = false
        try perform {
            guard !performed else { throw Failure.repeatedEffect }
            performed = true
            active = true
            defer { active = false }
            result = .some(try work())
        }
        guard performed, let result else { throw Failure.effectNotPerformed }
        return result
    }
}

/// Archive-side nested entry for shared/extension writers (#245), bound
/// closure-shaped so extension processes never import app-target types (central's
/// ArchiveNestedGenerationBoundary lives in Ate/Store). Identical contract: runs
/// UNDER the caller's held writer-gate effect; must not open or flock any lock
/// file; refuses while an unresolved archive transaction exists; commits exactly
/// one UInt64 generation advance after a successful covered unit. A throwing
/// work commits nothing. Read-only validation never goes through this entry:
/// reads must not advance the generation.
struct SharedArchiveNestedLeaseBoundary {
    /// The nested-lease runner. Called with the unit of work; it must run the
    /// work exactly once, synchronously, and throw without committing when the
    /// archive chain is unresolved.
    var run: (() throws -> Void) throws -> Void

    /// No archive binding: effects run directly. For legacy/test graphs and for
    /// callers whose writes never touch archive-covered data.
    static let none = SharedArchiveNestedLeaseBoundary { try $0() }

    func withNestedLease<T>(_ work: () throws -> T) throws -> T {
        var result: T?
        var performed = false
        try run {
            performed = true
            result = .some(try work())
        }
        guard performed, let result else { throw SharedWriterBoundary.Failure.effectNotPerformed }
        return result
    }
}

/// Cross-process writer gate for the App Group shared by the app and its
/// extensions (#245, shared/extension writers). Depends on Foundation and the
/// Shared/ types only, never on app-target types, so every target that compiles
/// Shared/ can use it. Hardening mirrors Ate/Store/AccountWriterGate.swift:
/// lstat/O_NOFOLLOW path validation, a non-blocking exclusive flock (busy is an
/// error, never a retry), and an atomic durable UUID epoch (tmp file, full-write
/// loop, fsync + F_FULLFSYNC, rename, parent-dir fsync, read-back verify). A
/// corrupt epoch is never silently repaired.
///
/// Every writer effect requires a captured writer epoch and, under the same
/// flock: refuses while a retained reset control record exists (via the injected
/// strict reader), re-validates the epoch (a released reset must have advanced
/// it, so pre-reset writes can never recreate erased data), then runs the effect
/// inside the injected archive nested lease (one generation advance per
/// committed unit). The flock covers the whole read-modify-write plus the
/// in-memory publish, never only the final save, and is never held across an
/// await (shared call sites are synchronous). Validation alone is a post-await
/// stale-result check, never effect authorization, and never advances the
/// archive generation.
final class SharedFileWriterGate {
    enum Mode: Equatable { case appGroup, appOnly }
    enum Error: Swift.Error {
        case unsafePath, busy, corruptEpoch, persistenceUnverified, resetPending, staleLease
    }

    private let directory: URL?
    private let resetPending: () throws -> Bool
    private let archive: SharedArchiveNestedLeaseBoundary
    private let processLock = NSRecursiveLock()
    /// The lease whose effect currently holds this process's flock, if any.
    private var activeLease: UUID?
    /// App-only mode has no shared durable control; its epoch is process-local.
    private var appOnlyEpoch = UUID()

    /// App-group mode. The directory must already exist (the composition point
    /// creates it) and must be a real directory, never a link. `resetPending`
    /// must be the SAME strict durable reset-control reader every process uses;
    /// `archive` is the archive nested lease for this process's writes.
    init(directory: URL,
         resetPending: @escaping () throws -> Bool,
         archive: SharedArchiveNestedLeaseBoundary) throws {
        guard directory.isFileURL, directory.standardizedFileURL == directory else { throw Error.unsafePath }
        self.directory = directory
        self.resetPending = resetPending
        self.archive = archive
        try Self.validateDirectory(directory)
    }
    private init(appOnly: Bool) {
        directory = nil
        resetPending = { false }
        archive = .none
    }

    /// Explicit app-only mode: process-local exclusion only, no cross-process
    /// coordination, no durable epoch, no reset control and no archive chain.
    /// Only for an installation that genuinely has no shared container
    /// (free-account sideload); never a silent fallback pretending extensions
    /// share one.
    static let appOnly = SharedFileWriterGate(appOnly: true)

    var mode: Mode { directory == nil ? .appOnly : .appGroup }

    private static func validateDirectory(_ directory: URL) throws {
        var metadata = stat()
        guard lstat(directory.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR else { throw Error.unsafePath }
    }

    private func lock(_ directory: URL) throws -> Int32 {
        try Self.validateDirectory(directory)
        let file = directory.appendingPathComponent(SharedWriterControl.lockFileName)
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Error.unsafePath }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG else {
            close(fd); throw Error.unsafePath
        }
        guard shared_writer_flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw Error.busy }
        return fd
    }
    private func unlock(_ fd: Int32) { _ = shared_writer_flock(fd, LOCK_UN); close(fd) }

    private var epochFile: URL {
        directory!.appendingPathComponent(SharedWriterControl.epochFileName)
    }
    private func readEpoch() throws -> UUID? {
        var metadata = stat()
        guard lstat(epochFile.path, &metadata) == 0 else {
            if errno == ENOENT { return nil }
            throw Error.corruptEpoch
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              let text = String(data: try Data(contentsOf: epochFile), encoding: .utf8),
              let epoch = UUID(uuidString: text) else { throw Error.corruptEpoch }
        return epoch
    }
    private func saveEpoch(_ epoch: UUID) throws {
        guard let directory else { throw Error.unsafePath }
        _ = try readEpoch() // never silently repair corrupt control
        let file = directory.appendingPathComponent(".writer-epoch-\(UUID().uuidString).tmp")
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Error.persistenceUnverified }
        var renamed = false
        defer { close(fd); if !renamed { try? FileManager.default.removeItem(at: file) } }
        let bytes = Data(epoch.uuidString.utf8)
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { throw Error.persistenceUnverified }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Error.persistenceUnverified }
                offset += count
            }
        }
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0,
              rename(file.path, epochFile.path) == 0 else { throw Error.persistenceUnverified }
        renamed = true
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw Error.persistenceUnverified }
        defer { close(parent) }
        guard fsync(parent) == 0, try readEpoch() == epoch else { throw Error.persistenceUnverified }
    }

    /// The current writer epoch, captured under the flock and persisted on first
    /// use. Refuses while a reset control record exists. Re-validate the lease
    /// after any await that happened outside a gated section before trusting
    /// state read earlier.
    func captureEpoch() throws -> UUID {
        guard directory != nil else { return appOnlyEpoch }
        processLock.lock()
        defer { processLock.unlock() }
        if let activeLease { return activeLease }
        let fd = try lock(directory!)
        defer { unlock(fd) }
        guard try !resetPending() else { throw Error.resetPending }
        if let epoch = try readEpoch() { return epoch }
        let epoch = UUID()
        try saveEpoch(epoch)
        return epoch
    }

    /// Runs the whole effect under the exclusive OS flock: reset-control check,
    /// epoch re-validation, then the archive nested lease around the effect.
    /// Reentrant within the process for the SAME lease: a nested effect runs
    /// under the outer one and never touches the OS lock again.
    func withWriterEffect<T>(_ lease: UUID, _ effect: () throws -> T) throws -> T {
        guard directory != nil else {
            guard appOnlyEpoch == lease else { throw Error.staleLease }
            processLock.lock()
            defer { processLock.unlock() }
            return try effect()
        }
        processLock.lock()
        defer { processLock.unlock() }
        if let active = activeLease {
            guard active == lease else { throw Error.staleLease }
            return try archive.withNestedLease { try effect() }
        }
        let fd = try lock(directory!)
        defer { unlock(fd) }
        guard try !resetPending() else { throw Error.resetPending }
        guard try readEpoch() == lease else { throw Error.staleLease }
        activeLease = lease
        defer { activeLease = nil }
        return try archive.withNestedLease { try effect() }
    }

    /// Throws when the lease is no longer valid under the flock. Validation is
    /// only a post-await stale-result check, never effect authorization, and it
    /// never enters the archive nested lease: reads must not advance the
    /// generation.
    func validate(_ lease: UUID) throws {
        guard directory != nil else {
            guard appOnlyEpoch == lease else { throw Error.staleLease }
            return
        }
        processLock.lock()
        defer { processLock.unlock() }
        if let active = activeLease {
            guard active == lease else { throw Error.staleLease }
            return
        }
        let fd = try lock(directory!)
        defer { unlock(fd) }
        guard try !resetPending() else { throw Error.resetPending }
        guard try readEpoch() == lease else { throw Error.staleLease }
    }

    /// The production boundary backed by this gate. Captures the writer epoch on
    /// entry (throwing while a reset control record exists); every effect
    /// re-validates that epoch under the flock and runs inside the archive
    /// nested lease.
    func makeBoundary() throws -> SharedWriterBoundary {
        let lease = try captureEpoch()
        return SharedWriterBoundary { effect in try withWriterEffect(lease, effect) }
    }
}

/// The one composition point that resolves the shared control directory from the
/// resolved App Group. The gate itself always takes the directory, the strict
/// reset-control reader and the archive nested lease as injected parameters.
/// Canonical startup must inject THIS SAME directory into the account/reset
/// composition so every writer gate shares one flock, and install the boundary
/// per process: in the APP process, `SharedWriterBoundary.adapting` wrapping the
/// already-held central boundary; in EXTENSION processes, the standalone
/// gate-backed boundary from here.
enum SharedWriterGateComposition {
    enum ResolutionError: Swift.Error { case appGroupUnavailable }

    /// `<resolved app-group container>/AteStateControl`, created if missing. Fails
    /// closed when the App Group is unavailable: the caller chooses explicit
    /// app-only mode instead of pretending extensions share a container.
    static func controlDirectory(
        resolution: AppGroupResolver.Resolution = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard resolution.available,
              let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: resolution.id) else {
            throw ResolutionError.appGroupUnavailable
        }
        let directory = container.appendingPathComponent(SharedWriterControl.directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeGate(
        resetPending: @escaping () throws -> Bool,
        archive: SharedArchiveNestedLeaseBoundary,
        resolution: AppGroupResolver.Resolution = .current,
        fileManager: FileManager = .default
    ) throws -> SharedFileWriterGate {
        try SharedFileWriterGate(
            directory: controlDirectory(resolution: resolution, fileManager: fileManager),
            resetPending: resetPending, archive: archive)
    }

    /// The flock-backed production boundary for an extension process. Install
    /// once during startup via SharedWriterBoundary.install before ordinary
    /// writers run.
    static func makeBoundary(
        resetPending: @escaping () throws -> Bool,
        archive: SharedArchiveNestedLeaseBoundary,
        resolution: AppGroupResolver.Resolution = .current,
        fileManager: FileManager = .default
    ) throws -> SharedWriterBoundary {
        try makeGate(resetPending: resetPending, archive: archive,
                     resolution: resolution, fileManager: fileManager).makeBoundary()
    }

    /// Explicit app-only boundary for an installation with no shared container.
    static func makeAppOnlyBoundary() throws -> SharedWriterBoundary {
        try SharedFileWriterGate.appOnly.makeBoundary()
    }
}
