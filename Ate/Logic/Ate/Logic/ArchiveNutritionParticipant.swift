import Foundation

/// Exact raw before-images, with no repository load/loadState migration side effects.
/// This is a COMPONENT participant, not the entire outer archive participant.
/// UserDefaults readback is same-process verification, not power-loss durability.
@MainActor
final class ArchiveNutritionParticipant {
    enum Boundary: CaseIterable, Equatable {
        case beforeGoals, afterGoals, beforeLegacyGoalsRemoval, afterLegacyGoalsRemoval
        case beforeDiary, afterDiary, beforeVerify
    }
    enum Failure: Error { case readbackMismatch, changedSinceSnapshot }
    private let diary: NutritionDiaryRepository
    private let goals: NutritionGoalsRepository
    private let oldDiary: Data?
    private let oldGoalFile: Data?
    private let oldLegacyGoals: Data?
    private let newDiary: Data
    private let newGoalFile: Data?
    private let checkpoint: (Boundary) throws -> Void
    private let validateLease: () throws -> Void
    private var attempted = false

    init(diary: NutritionDiaryRepository, goals: NutritionGoalsRepository,
         incomingDiary: [NutritionDiaryEntry], incomingGoals: DailyNutritionGoals,
         validateLease: @escaping () throws -> Void = {},
         checkpoint: @escaping (Boundary) throws -> Void = { _ in }) throws {
        self.diary = diary; self.goals = goals; self.checkpoint = checkpoint
        self.validateLease = validateLease
        oldDiary = diary.defaults.data(forKey: NutritionDiaryRepository.storageKey)
        oldGoalFile = try goals.storage.read()
        oldLegacyGoals = goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey)
        // Decode without migration. Refuse corrupt original rather than erase the only copy.
        let existing = try oldDiary.map { try JSONDecoder().decode([NutritionDiaryEntry].self, from: $0) } ?? []
        if let oldGoalFile { _ = try JSONDecoder().decode(DailyNutritionGoals.self, from: oldGoalFile) }
        if let oldLegacyGoals { _ = try JSONDecoder().decode(DailyNutritionGoals.self, from: oldLegacyGoals) }
        guard incomingDiary.allSatisfy(FoodJournalStore.validMeal) else {
            throw AteDataArchiveError.invalidNutritionEntry
        }
        var ids = Set(existing.map(\.id))
        let additions = incomingDiary.filter { ids.insert($0.id).inserted }
        newDiary = try JSONEncoder().encode(existing + additions)
        newGoalFile = incomingGoals.isEmpty ? nil : try JSONEncoder().encode(incomingGoals)
    }

    func participant() -> ArchiveRestoreParticipant {
        ArchiveRestoreParticipant(apply: { try self.apply() }, verify: { try self.verify() },
                                  rollback: { try self.rollback() })
    }

    private func apply() throws {
        try validateLease()
        guard !attempted,
              diary.defaults.data(forKey: NutritionDiaryRepository.storageKey) == oldDiary,
              try goals.storage.read() == oldGoalFile,
              goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey) == oldLegacyGoals else {
            throw Failure.changedSinceSnapshot
        }
        attempted = true
        try checkpoint(.beforeGoals)
        try validateLease()
        try setGoalFile(newGoalFile)
        try checkpoint(.afterGoals)
        try checkpoint(.beforeLegacyGoalsRemoval)
        try validateLease()
        goals.defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
        try checkpoint(.afterLegacyGoalsRemoval)
        try checkpoint(.beforeDiary)
        try validateLease()
        diary.defaults.set(newDiary, forKey: NutritionDiaryRepository.storageKey)
        try checkpoint(.afterDiary)
    }

    private func verify() throws {
        try validateLease()
        try checkpoint(.beforeVerify)
        guard try goals.storage.read() == newGoalFile,
              goals.defaults.object(forKey: DailyNutritionGoals.defaultsKey) == nil,
              diary.defaults.data(forKey: NutritionDiaryRepository.storageKey) == newDiary else {
            throw Failure.readbackMismatch
        }
    }

    private func rollback() throws {
        guard attempted else { return }
        var failures: [String] = []
        // Each component may be unchanged or the exact planned value. A third
        // value (including foreign deletion) belongs to another writer; preserve it.
        do {
            try validateLease()
            let current = try goals.storage.read()
            guard current == oldGoalFile || current == newGoalFile else { throw Failure.changedSinceSnapshot }
            if current != oldGoalFile { try validateLease(); try setGoalFile(oldGoalFile) }
        } catch { failures.append("goals file: \(error)") }
        do {
            try validateLease()
            let current = goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey)
            guard current == oldLegacyGoals || current == nil else { throw Failure.changedSinceSnapshot }
            if current != oldLegacyGoals {
                try validateLease()
                restore(oldLegacyGoals, defaults: goals.defaults, key: DailyNutritionGoals.defaultsKey)
            }
        } catch { failures.append("legacy goals: \(error)") }
        do {
            try validateLease()
            let current = diary.defaults.data(forKey: NutritionDiaryRepository.storageKey)
            guard current == oldDiary || current == newDiary else { throw Failure.changedSinceSnapshot }
            if current != oldDiary {
                try validateLease()
                restore(oldDiary, defaults: diary.defaults, key: NutritionDiaryRepository.storageKey)
            }
        } catch { failures.append("diary: \(error)") }
        do {
            guard try goals.storage.read() == oldGoalFile else { throw Failure.readbackMismatch }
        } catch { failures.append("goals readback: \(error)") }
        if goals.defaults.data(forKey: DailyNutritionGoals.defaultsKey) != oldLegacyGoals {
            failures.append("legacy goals readback")
        }
        if diary.defaults.data(forKey: NutritionDiaryRepository.storageKey) != oldDiary {
            failures.append("diary readback")
        }
        if !failures.isEmpty {
            throw ArchiveRestoreFailure.recoveryRequired(original: "nutrition rollback", compensationFailures: failures)
        }
    }

    private func setGoalFile(_ data: Data?) throws {
        if let data { try goals.storage.write(data) } else { try goals.storage.remove() }
    }
    private func restore(_ data: Data?, defaults: UserDefaults, key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
