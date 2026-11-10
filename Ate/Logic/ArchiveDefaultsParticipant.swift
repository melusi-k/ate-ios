import Foundation

/// Recovery verifies exact newly planned bytes, not semantic JSON equality. Separate
/// encoders must produce identical object-key ordering for the participant and its
/// recorded after-image. Raw before-images are retained unchanged.
enum ArchiveRestoreEncoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// PREP ONLY. No production call sites; component participant, not the full outer.
/// Raw before-images for the archive-owned UserDefaults keys: settings, timer prefs
/// and sync metadata. Sync meta is snapshotted and guarded but never written here:
/// stampChanges/scheduleSync stay deferred until activation decides the commit.
/// UserDefaults readback is same-process verification, not power-loss durability.
@MainActor
final class ArchiveDefaultsParticipant {
    enum Boundary: CaseIterable, Equatable {
        case beforeSettings, afterSettings, beforeTimer, afterTimer, beforeVerify
    }
    enum Failure: Error { case changedSinceSnapshot, readbackMismatch }

    static let settingsKey = "ate.settings.v1"
    static let timerKey = "ate.timerprefs.v1"
    static let syncMetaKey = "ate.sync.v1"

    private let defaults: UserDefaults
    private let oldSettings: Data?
    private let oldTimer: Data?
    private let oldSyncMeta: Data?
    private let newSettings: Data
    private let newTimer: Data
    private let checkpoint: (Boundary) throws -> Void
    /// Bound to lease.validate at composition; called before EVERY write/undo write.
    private let validate: () throws -> Void
    private var attempted = false

    /// Captures raw bytes and pre-encodes replacements. No write happens in init.
    /// Encoding uses a deterministic JSONEncoder for byte-exact recovery images.
    init(defaults: UserDefaults, settings: AppSettings, timerPrefs: TimerPrefs,
         checkpoint: @escaping (Boundary) throws -> Void = { _ in },
         validate: @escaping () throws -> Void = {}) throws {
        self.defaults = defaults; self.checkpoint = checkpoint; self.validate = validate
        oldSettings = defaults.data(forKey: Self.settingsKey)
        oldTimer = defaults.data(forKey: Self.timerKey)
        oldSyncMeta = defaults.data(forKey: Self.syncMetaKey)
        newSettings = try ArchiveRestoreEncoding.encoder().encode(settings)
        newTimer = try ArchiveRestoreEncoding.encoder().encode(timerPrefs)
    }

    func participant() -> ArchiveRestoreParticipant {
        ArchiveRestoreParticipant(apply: { try self.apply() }, verify: { try self.verify() },
                                  rollback: { try self.rollback() })
    }

    private func apply() throws {
        guard !attempted,
              defaults.data(forKey: Self.settingsKey) == oldSettings,
              defaults.data(forKey: Self.timerKey) == oldTimer,
              defaults.data(forKey: Self.syncMetaKey) == oldSyncMeta else {
            throw Failure.changedSinceSnapshot
        }
        attempted = true
        try checkpoint(.beforeSettings)
        try validate()
        defaults.set(newSettings, forKey: Self.settingsKey)
        try checkpoint(.afterSettings)
        try checkpoint(.beforeTimer)
        try validate()
        defaults.set(newTimer, forKey: Self.timerKey)
        try checkpoint(.afterTimer)
    }

    private func verify() throws {
        try checkpoint(.beforeVerify)
        guard defaults.data(forKey: Self.settingsKey) == newSettings,
              defaults.data(forKey: Self.timerKey) == newTimer,
              defaults.data(forKey: Self.syncMetaKey) == oldSyncMeta else {
            throw Failure.readbackMismatch
        }
    }

    /// Guarded per-key compensation: a key is restored ONLY when its current bytes
    /// equal what this participant wrote (or it already matches the before-image).
    /// Any other value is a concurrent write: PRESERVED and surfaced, never
    /// overwritten. Sync meta is guarded by precheck/readback but never rewritten,
    /// so it needs no restore.
    private func rollback() throws {
        guard attempted else { return }
        var failures: [String] = []
        try reconcileKey(Self.settingsKey, old: oldSettings, new: newSettings, name: "settings", failures: &failures)
        try reconcileKey(Self.timerKey, old: oldTimer, new: newTimer, name: "timer", failures: &failures)
        if !failures.isEmpty {
            throw ArchiveRestoreFailure.recoveryRequired(original: "settings/timer rollback",
                                                         compensationFailures: failures)
        }
    }

    private func reconcileKey(_ key: String, old: Data?, new: Data, name: String, failures: inout [String]) throws {
        let current = defaults.data(forKey: key)
        if current == old { return }                 // already before-image
        if current == new {                          // our write: safe to restore
            do { try validate() } catch {
                failures.append("\(name): lease validation failed: \(error)")
                throw ArchiveRestoreFailure.recoveryRequired(original: "settings/timer rollback interrupted",
                                                             compensationFailures: failures)
            }
            restore(old, key: key)
            if defaults.data(forKey: key) != old { failures.append("\(name) readback") }
        } else {                                     // concurrent write: preserve
            failures.append("\(name): concurrent change preserved, not reverted")
        }
    }

    private func restore(_ data: Data?, key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// PREP ONLY. Sequences component participants as one outer participant for
/// JournalArchiveRestore.execute. Rollback attempts EVERY component independently
/// and aggregates failures; one failed compensation never suppresses another.
@MainActor
struct ArchiveOuterComposite {
    let components: [ArchiveRestoreParticipant]

    func participant() -> ArchiveRestoreParticipant {
        ArchiveRestoreParticipant(
            apply: { for c in components { try c.apply() } },
            verify: { for c in components { try c.verify() } },
            rollback: {
                var failures: [String] = []
                for (i, c) in components.enumerated() {
                    do { try c.rollback() } catch { failures.append("component \(i): \(error)") }
                }
                if !failures.isEmpty {
                    throw ArchiveRestoreFailure.recoveryRequired(original: "outer rollback",
                                                                 compensationFailures: failures)
                }
            })
    }
}
