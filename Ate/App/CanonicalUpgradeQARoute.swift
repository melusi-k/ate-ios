#if DEBUG
import SwiftUI
import SwiftData

/// Disk-backed synthetic upgrade world used ONLY by -UITesting + -qaCanonicalUpgrade.
/// No standard defaults, production Journal database, real meals or real backups are touched.
/// The explicit UUID namespace survives app termination so a second launch reads disk truth.
/// No production activation or export/reset/recovery parity is implied by this QA route.
@MainActor
enum CanonicalUpgradeQARoute {
    static let flag = "-qaCanonicalUpgrade"
    static let mealID = UUID(uuidString: "24500000-0000-4000-8000-000000000002")!
    static var requested: Bool {
        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains(flag)
    }
    static func prepareIfRequested() -> FoodJournalRuntime? {
        guard requested else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count,
              let identity = UUID(uuidString: args[i + 1]) else {
            preconditionFailure("Upgrade QA requires an explicit UUID namespace")
        }
        do {
            let suite = "ate.qa.canonical-upgrade.\(identity.uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Upgrade QA defaults unavailable")
            }
            let root = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("AteQAUpgrade", isDirectory: true)
                .appendingPathComponent(identity.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let container = try ModelContainer(for: JournalEntry.self, JournalMealPayload.self,
                configurations: ModelConfiguration(url: root.appendingPathComponent("journal.store")))
            let journal = JournalStore(container: container, openState: .ok)
            let goals = NutritionGoalsRepository(defaults: defaults,
                storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json")))
            let seededKey = "ate.qa.upgrade.seeded"
            if !defaults.bool(forKey: seededKey) {
                // Refuse an ambiguous partial seed rather than delete/reseed its saved state.
                guard defaults.data(forKey: NutritionDiaryRepository.storageKey) == nil,
                      try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).isEmpty else {
                    preconditionFailure("Upgrade QA partial seed requires a fresh namespace")
                }
                let meal = NutritionDiaryEntry(id: mealID, foodName: "Sample upgrade lunch", date: .now,
                    meal: .lunch, quantity: 1, quantityUnit: "portion", servings: 1,
                    source: .userProvided, sourceName: "You",
                    nutrientsPerServing: NutritionSnapshot(energyKcal: 715, proteinGrams: 55,
                        carbohydratesGrams: nil, fatGrams: 55, fibreGrams: nil))
                defaults.set(try JSONEncoder().encode([meal]), forKey: NutritionDiaryRepository.storageKey)
                try journal.saveManual(text: "Sample reflection before upgrade")
                var initialGoals = DailyNutritionGoals()
                initialGoals.energyKcal = 2345
                try goals.save(initialGoals)
                defaults.set(true, forKey: seededKey)
            }
            return FoodJournalRuntime(journal: journal,
                goalsRepository: goals,
                defaults: defaults, migrationBackupDirectory: root.appendingPathComponent("legacy-backups"),
                repairBackupDirectory: root.appendingPathComponent("repair-backups"),
                afterRestoreCommit: {
                    if args.contains("-qaRestoreVerificationFailure") { throw RestoreFixtureError.verification }
                })
        } catch {
            preconditionFailure("Upgrade QA cannot open its isolated disk world: \(error)")
        }
    }
    static func rootView() -> AnyView? {
        guard requested else { return nil }
        return AnyView(CanonicalUpgradeRootView())
    }
    enum RestoreFixtureError: Error { case verification }
    static func sampleBackup() throws -> ReviewedMealBackup {
        let meal = NutritionDiaryEntry(id: UUID(uuidString: "24500000-0000-4000-8000-000000000003")!,
            foodName: "Sample recovered snack", date: Date(timeIntervalSince1970: 1_794_000_000),
            meal: .snack, quantity: 1, quantityUnit: "portion", servings: 1,
            source: .userProvided, sourceName: "You", nutrientsPerServing: NutritionSnapshot(
                energyKcal: 200, proteinGrams: 5, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
            dayKey: "2026-11-06")
        return try ReviewedMealBackup(JSONEncoder().encode([meal]))
    }
}

/// The review sheet and controller are production views/verbs; only the selected input
/// and explicit verification checkpoint fault are synthetic. The real Files picker is
/// exercised separately for cancellation, not claimed by the synthetic review button.
@MainActor
private struct CanonicalUpgradeRootView: View {
    @Environment(AppStore.self) private var store
    @State private var reviewedBackup: ReviewedMealBackup?
    @State private var controller: NutritionDiaryController?
    @State private var refresh = UUID()
    var body: some View {
        NavigationStack {
            JournalTimelineView().id(refresh)
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Review sample backup") { reviewedBackup = try? CanonicalUpgradeQARoute.sampleBackup() }
                            .accessibilityIdentifier("upgradeQA.backupReview")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.nutritionGoals) { Text("Goals") }
                            .accessibilityIdentifier("upgradeQA.goals")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.nutritionDiary) { Text("Food diary") }
                            .accessibilityIdentifier("upgradeQA.diary")
                    }
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .onAppear {
            if controller == nil, let runtime = store.foodJournalRuntime {
                controller = NutritionDiaryController(coordinator: runtime.coordinator,
                    goalsRepository: runtime.goalsRepository, repair: runtime.repair)
            }
        }
        .sheet(item: $reviewedBackup, onDismiss: { refresh = UUID() }) { backup in
            if let controller {
                ReviewedMealBackupSheet(backup: backup) { try controller.restoreReviewedMealBackup(backup) }
            }
        }
    }
}
#endif
