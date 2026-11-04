import Foundation
import Observation

/// What currently blocks or failed on the diary, and which honest route resolves it.
enum NutritionDiaryIssue: Equatable {
    /// Legacy diary data still exists and needs explicit repair (undecodable bytes, or invalid /
    /// duplicate records) before migration can finish. The repair route backs up exact bytes and
    /// never writes canonical records itself.
    case legacyRepairNeeded(reason: String)
    /// Migration cannot finish for a reason legacy repair does not fix (for example the journal is
    /// not durably available or its backup write failed). Nothing was lost; retry only.
    case migrationRetryNeeded(reason: String)
    /// Reading canonical meals failed. The diary must never present this as an empty diary.
    case readFailed(reason: String)

    var reason: String {
        switch self {
        case .legacyRepairNeeded(let reason), .migrationRetryNeeded(let reason), .readFailed(let reason):
            return reason
        }
    }
}

/// Diary reads and writes against the canonical Food Journal coordinator (#179 editing and
/// weekly totals). Every mutation goes through the coordinator's throwing verbs and state is
/// reloaded from the canonical store after each isolated success - never assumed, never a
/// legacy UserDefaults write. Unactivated candidate: production composition (which coordinator,
/// repair adapter and backup directory) stays with central integration.
@MainActor @Observable
final class NutritionDiaryController {
    let coordinator: FoodJournalCoordinator
    let goalsRepository: NutritionGoalsRepository
    /// The explicit pre-migration repair adapter, injected by composition. Production wiring must
    /// point it at Documents/NutritionDiaryCorruptBackups, the existing diary recovery location.
    let repairAdapter: LegacyDiaryRepair
    let calendar: Calendar

    private(set) var entries: [NutritionDiaryEntry] = []
    private(set) var issue: NutritionDiaryIssue?
    var selectedDayKey: String

    init(coordinator: FoodJournalCoordinator,
         goalsRepository: NutritionGoalsRepository = NutritionGoalsRepository(),
         repair: LegacyDiaryRepair,
         selectedDayKey: String? = nil,
         calendar: Calendar = .autoupdatingCurrent) {
        self.coordinator = coordinator
        self.goalsRepository = goalsRepository
        self.repairAdapter = repair
        self.calendar = calendar
        self.selectedDayKey = selectedDayKey ?? NutritionDiaryDayKey.make(.now, calendar: calendar)
    }

    var selectedDate: Date {
        NutritionDiaryDayKey.date(for: selectedDayKey, calendar: calendar) ?? calendar.startOfDay(for: .now)
    }
    var dayEntries: [NutritionDiaryEntry] { entries.filter { $0.dayKey == selectedDayKey } }
    var dayTotals: NutritionDayTotals { NutritionDayTotals.calculate(entries: dayEntries) }
    var weekInterval: DateInterval? { NutritionWeekTotals.weekInterval(containing: selectedDate, calendar: calendar) }
    var weekEntries: [NutritionDiaryEntry] { NutritionWeekTotals.entries(entries, inWeekOf: selectedDate, calendar: calendar) }
    var weekTotals: NutritionDayTotals { NutritionDayTotals.calculate(entries: weekEntries) }
    /// True when the selected day sits in the device's current week, so the section can say "This week".
    var selectedWeekIsCurrent: Bool {
        guard let week = weekInterval,
              let current = NutritionWeekTotals.weekInterval(containing: .now, calendar: calendar) else { return false }
        return week.start == current.start
    }

    func goals() -> DailyNutritionGoals? { try? goalsRepository.load() }

    /// The actual journal open state, passed through live from the coordinator. Composition owns
    /// any banner, but the diary must never silently present a recovered journal as ordinary
    /// history: non-durable states already surface as typed issues through the migration check,
    /// and `.recovered` is readable here so the view can say what happened.
    var journalOpenState: JournalOpenState { coordinator.openState }

    /// Reads through the coordinator. A failure never masquerades as an empty diary: entries are
    /// cleared and the typed issue is presented with its repair or retry route instead.
    func reload() {
        do {
            entries = try coordinator.readMeals()
            issue = nil
        } catch {
            entries = []
            issue = classify(error)
        }
    }

    /// Mutations throw so the caller keeps its draft and shows the reason. The coordinator
    /// rechecks migration on every verb, so a blocked diary can never be written through here.
    func add(_ entry: NutritionDiaryEntry) throws {
        try coordinator.saveMeal(entry)
        reload()
    }

    func update(_ entry: NutritionDiaryEntry) throws {
        try coordinator.updateMeal(entry)
        reload()
    }

    func delete(id: UUID) throws {
        try coordinator.deleteMeal(id: id)
        reload()
    }

    /// Retries reading (which re-runs migration) after repair or a transient failure.
    /// Returns true when the diary is readable again.
    @discardableResult
    func retry() -> Bool {
        reload()
        return issue == nil
    }

    /// Maps a failure to its honest route by legacy CONTENT, not mere presence. Repair is only
    /// offered when the payload actually needs it: undecodable bytes, or decodable records with
    /// invalid or duplicate rows. A fully valid legacy diary means the failure is environmental
    /// (durability, read, import, verification or backup) and repair would be a dead end - the
    /// repair view lists nothing and its reset refuses decodable data - so the diary offers retry
    /// with the real reason instead. Classification never writes anything.
    func classify(_ error: Error) -> NutritionDiaryIssue {
        guard let access = error as? FoodJournalCoordinator.AccessError else {
            return .readFailed(reason: error.localizedDescription)
        }
        switch access {
        case .legacyCorrupt:
            return .legacyRepairNeeded(reason: "The older diary couldn't be decoded. Repair it below, then retry.")
        case .migrationFailed(let reason):
            do {
                let snapshot = try repairAdapter.snapshot()
                guard !snapshot.invalidIndices.isEmpty || !snapshot.duplicateIndices.isEmpty else {
                    return .migrationRetryNeeded(reason: reason)
                }
                return .legacyRepairNeeded(reason: reason)
            } catch LegacyDiaryRepairError.unavailable {
                return .migrationRetryNeeded(reason: reason)
            } catch {
                // Undecodable or otherwise unreadable legacy bytes: the repair view owns that route.
                return .legacyRepairNeeded(reason: reason)
            }
        }
    }
}
