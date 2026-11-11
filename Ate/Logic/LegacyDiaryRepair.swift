import Foundation

enum LegacyDiaryRepairError: Error, Equatable {
    case unavailable
    case undecodable
    case changedSinceReview
    case invalidReplacement
    case backupFailed
    case verificationFailed
}

/// A snapshot for explicit user-directed repair before canonical migration. Never a fallback writer.
/// Index identity matters: duplicate legacy UUIDs must remain individually repairable/removable.
struct LegacyDiaryRepairSnapshot {
    let originalBytes: Data
    let entries: [NutritionDiaryEntry]
    @MainActor var invalidIndices: [Int] { entries.indices.filter { !FoodJournalStore.validMeal(entries[$0]) } }
    var duplicateIndices: [Int] {
        var seen = Set<UUID>()
        return entries.indices.filter { !seen.insert(entries[$0].id).inserted }
    }
}

@MainActor
struct LegacyDiaryRepair {
    let repository: NutritionDiaryRepository
    let backupDirectory: URL
    var writerBoundary: FoodJournalWriterBoundary = .legacy

    func snapshot() throws -> LegacyDiaryRepairSnapshot {
        guard let raw = repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) else { throw LegacyDiaryRepairError.unavailable }
        guard let entries = try? JSONDecoder().decode([NutritionDiaryEntry].self, from: raw) else { throw LegacyDiaryRepairError.undecodable }
        return LegacyDiaryRepairSnapshot(originalBytes: raw, entries: entries)
    }

    /// Removes only the reviewed row. Other invalid rows remain visible for the next repair.
    func remove(index: Int, from snapshot: LegacyDiaryRepairSnapshot) throws {
        guard snapshot.entries.indices.contains(index) else { throw LegacyDiaryRepairError.changedSinceReview }
        var next = snapshot.entries
        next.remove(at: index)
        try commit(next, replacing: snapshot)
    }

    /// Editing does not change UUID/day/date unless the caller deliberately supplies them.
    func replace(index: Int, with entry: NutritionDiaryEntry, in snapshot: LegacyDiaryRepairSnapshot) throws {
        guard snapshot.entries.indices.contains(index) else { throw LegacyDiaryRepairError.changedSinceReview }
        guard FoodJournalStore.validMeal(entry) else { throw LegacyDiaryRepairError.invalidReplacement }
        var next = snapshot.entries
        next[index] = entry
        try commit(next, replacing: snapshot)
    }

    /// Explicit confirmation-only recovery for undecodable bytes. Never accept a decodable
    /// array here: its individual records belong in the repair list rather than a reset.
    func backUpAndResetUndecodableData() throws {
        return try writerBoundary.withEffect {
            guard let original = repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) else { throw LegacyDiaryRepairError.unavailable }
            guard (try? JSONDecoder().decode([NutritionDiaryEntry].self, from: original)) == nil else { throw LegacyDiaryRepairError.invalidReplacement }
            let backup = backupDirectory.appendingPathComponent("nutrition-diary-undecodable-\(UUID().uuidString).json")
            do {
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try original.write(to: backup, options: .atomic)
                guard try Data(contentsOf: backup) == original else { throw LegacyDiaryRepairError.backupFailed }
            } catch { throw LegacyDiaryRepairError.backupFailed }
            guard repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) == original else { throw LegacyDiaryRepairError.changedSinceReview }
            repository.clear()
            guard repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) == nil else { throw LegacyDiaryRepairError.verificationFailed }

        }
    }

    private func commit(_ entries: [NutritionDiaryEntry], replacing snapshot: LegacyDiaryRepairSnapshot) throws {
        return try writerBoundary.withEffect {
            guard repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) == snapshot.originalBytes else { throw LegacyDiaryRepairError.changedSinceReview }
            let next = try repository.prepare(entries)
            let backup = backupDirectory.appendingPathComponent("nutrition-diary-before-repair-\(UUID().uuidString).json")
            do {
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try snapshot.originalBytes.write(to: backup, options: .atomic)
                guard try Data(contentsOf: backup) == snapshot.originalBytes else { throw LegacyDiaryRepairError.backupFailed }
            } catch { throw LegacyDiaryRepairError.backupFailed }
            // Check again after disk IO so a changed live source is never overwritten from a stale screen.
            guard repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) == snapshot.originalBytes else { throw LegacyDiaryRepairError.changedSinceReview }
            repository.savePrepared(next)
            guard repository.defaults.data(forKey: NutritionDiaryRepository.storageKey) == next else { throw LegacyDiaryRepairError.verificationFailed }

        }
    }
}
