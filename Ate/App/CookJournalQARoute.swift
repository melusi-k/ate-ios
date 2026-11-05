#if DEBUG
import SwiftUI
import SwiftData

/// Opt-in only. Runtime session/history/outbox/reflections use per-launch isolated storage.
/// Existing app UI-test startup still resets standard test preferences and global services;
/// this is not whole-app hermeticity. Explicit cleanup removes the QA suite/temp directory.
/// A forced process termination can leave QA-only residue, never reused as test evidence.
@MainActor
enum CookJournalQARoute {
    static var requested: Bool {
        AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaCookJournalHost")
    }
    private static var suite: String?
    private static var root: URL?

    static func runtime() -> FoodJournalRuntime? {
        guard requested else { return nil }
        let id = UUID().uuidString
        let name = "ate.qa.cook-journal." + id
        guard let defaults = UserDefaults(suiteName: name) else { preconditionFailure("QA defaults unavailable") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        do { try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true) }
        catch { preconditionFailure("QA temporary directory unavailable") }
        suite = name
        root = temp
        let journal = JournalStore(inMemory: true)
        let goals = NutritionGoalsRepository(defaults: defaults,
            storage: FileNutritionGoalsStorage(fileURL: temp.appendingPathComponent("goals.json")))
        return FoodJournalRuntime(journal: journal, goalsRepository: goals, defaults: defaults,
                                  migrationBackupDirectory: temp.appendingPathComponent("migration"),
                                  repairBackupDirectory: temp.appendingPathComponent("repair"))
    }

    static func cleanup() {
        if let suite { UserDefaults.standard.removePersistentDomain(forName: suite) }
        if let root { try? FileManager.default.removeItem(at: root) }
        suite = nil; root = nil
    }

    static func prepare(_ store: AppStore) {
        guard requested else { return }
        let recipe = RecipeCard(id: "qa-cook-journal", title: "Original pap",
                                steps: [Step(order: 1, instruction: "Stir the pap.", timeSeconds: nil)])
        store.recipes = [recipe]
        if ProcessInfo.processInfo.arguments.contains("-qaCookJournalManualBlocker"), let runtime = store.foodJournalRuntime {
            let now = Date()
            let event = CookCompletionEvent(recipeID: recipe.id, recipeTitle: recipe.title, completedAt: now,
                                            dayKey: CookingHistory.shared.key(for: now), id: "cook-qa-blocked")
            do { try runtime.cookOutbox.enqueue(event) }
            catch { preconditionFailure("QA cook queue unavailable") }
            store.beginManualJournal()
            store.requestCookedReflection(event)
            return
        }
        store.beginCookSession(recipeID: recipe.id, factor: 1)
        if ProcessInfo.processInfo.arguments.contains("-qaCookJournalNavigation") {
            store.path = [.cook(recipe.id)]
        } else { store.cookTarget = CookTarget(id: recipe.id) }
    }
}
#endif

#if DEBUG
/// Explicit QA evidence route, not a replacement for ordinary Journal detail integration.
struct CookJournalQAInspector: ViewModifier {
    @Environment(AppStore.self) private var store
    private struct Inspection: Identifiable {
        let id = UUID()
        let detail: String
    }
    @State private var inspection: Inspection?
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if CookJournalQARoute.requested && inspection == nil && store.cookTarget == nil && !store.cookJournalViewVisible && store.cookedReflectionPresentedID == nil {
                VStack {
                    Button("Inspect saved cook note") {
                        let detail: String
                        do {
                            guard let runtime = store.foodJournalRuntime, let container = runtime.journal.container else {
                                inspection = Inspection(detail: "UNAVAILABLE"); return
                            }
                            let context = ModelContext(container)
                            let rows = try context.fetch(FetchDescriptor<JournalEntry>())
                            let pending = try runtime.pendingCookReflections()
                            detail = "rows=\(rows.count);pending=\(pending.count)\n" + rows.map { row in
                                "\(row.text)\n\(row.dayKey)\n\(row.recipeSnapshotsRaw)\nkind=\(row.kindRaw);health-empty=\(row.stateRaw.isEmpty ? "yes" : "NO")"
                            }.joined(separator: "\n")
                        } catch { detail = "READ FAILED" }
                        inspection = Inspection(detail: detail)
                    }.accessibilityIdentifier("cookJournal.qa.inspect")
                    Button("Finish cook QA") { CookJournalQARoute.cleanup() }
                        .accessibilityIdentifier("cookJournal.qa.cleanup")
                }.font(.caption).padding(8).background(.regularMaterial)
            }
        }
        .sheet(item: $inspection) { snapshot in
            VStack {
                ScrollView {
                    Text(snapshot.detail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("cookJournal.qa.detail").padding()
                }
                .frame(maxWidth: .infinity)
                Button("Finish cook QA") { CookJournalQARoute.cleanup(); inspection = nil }
                    .accessibilityIdentifier("cookJournal.qa.cleanup")
            }
                .presentationDetents([.large])
        }
    }
}
#endif
