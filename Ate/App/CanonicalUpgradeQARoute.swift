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
                defaults.set(true, forKey: seededKey)
            }
            return FoodJournalRuntime(journal: journal,
                goalsRepository: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: root.appendingPathComponent("goals.json"))),
                defaults: defaults, migrationBackupDirectory: root.appendingPathComponent("legacy-backups"),
                repairBackupDirectory: root.appendingPathComponent("repair-backups"))
        } catch {
            preconditionFailure("Upgrade QA cannot open its isolated disk world: \(error)")
        }
    }
    static func rootView() -> AnyView? {
        guard requested else { return nil }
        return AnyView(NavigationStack {
            JournalTimelineView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.nutritionDiary) { Text("Food diary") }
                            .accessibilityIdentifier("upgradeQA.diary")
                    }
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        })
    }
}
#endif
