import SwiftUI

@MainActor @Observable
final class InsightsModel {
    static let shared = InsightsModel()
    private(set) var health: HealthKitServicing
    var access: HealthAccess
    /// Beta debug picker: swap to a mock scenario ("" = live Apple Health).
    func useScenario(_ s: String, recipes: [RecipeCard]) async {
        UserDefaults.standard.set(s, forKey: HealthServiceFactory.debugKey)
        health = HealthServiceFactory.make(arguments: [])
        if health is MockHealthKitService { _ = await health.requestAccess() }
        await refresh(recipes: recipes)
    }
    var context: HealthContext?
    var loading = false
    init(health: HealthKitServicing = HealthServiceFactory.make()) { self.health = health; access = health.access }

    func connect(recipes: [RecipeCard]) async { access = await health.requestAccess(); await refresh(recipes: recipes) }
    func refresh(recipes: [RecipeCard]) async {
        access = health.access
        guard access == .requested else { context = nil; return }
        loading = true; defer { loading = false }
        let s = await health.summary(days: 7)
        guard let i = HealthInsightEngine.insight(for: s) else { context = nil; return }
        context = HealthContext(summary: s, insight: i,
                                suggestions: RecipeHealthMatcher.suggestions(for: i.state, recipes: recipes),
                                prompts: await JournalSuggestionService.prompts(for: i))
    }
}

/// More → Insights: "Your body today", "Suggested meals", "Reflect on your day", "Save to journal".
struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @State private var model = InsightsModel.shared
    @State private var draft = ""
    @State private var prompt: JournalPrompt?
    @State private var entries: [JournalEntry] = []
    @State private var openRecipe: RecipeSheetTarget?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Insights").font(AteFont.display(30)).accessibilityAddTraits(.isHeader)
                    bodyToday
                    if let c = model.context {
                        card("Suggested meals") {
                            Text(c.insight.state.mealFocus).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                            if c.suggestions.isEmpty {
                                Text("Save a few recipes and Ate will pick the ones that fit your day.").font(AteFont.body(14))
                                    .accessibilityIdentifier("insights.noSuggestions")
                            }
                            ForEach(c.suggestions) { s in
                                Button { openRecipe = RecipeSheetTarget(id: s.recipeID) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.title).font(AteFont.body(15, .semibold))
                                            Text(s.why).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                        }
                                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
                                    }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier("insights.suggestion")
                            }
                        }
                        card("Reflect on your day") {
                            ForEach(c.prompts) { p in
                                Button { prompt = p } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: prompt == p ? "largecircle.fill.circle" : "circle").foregroundStyle(Theme.primary)
                                        Text(p.text).font(AteFont.body(15)).multilineTextAlignment(.leading)
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("insights.prompt")
                            }
                            TextField("Write a few lines…", text: $draft, axis: .vertical).lineLimit(3...8)
                                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityIdentifier("insights.journalText")
                            Button("Save to journal") { save(c) }
                                .buttonStyle(.ate(.primary, full: true))
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("insights.save")
                            Text("Saved only on this iPhone. Ate can't write to Apple's Journal app.")
                                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    journalCard
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .pageWidth()
            }
        }
        .sheet(item: $openRecipe) { t in RecipeSheet(recipeID: t.id).environment(store) }
        .onChange(of: model.context?.insight.state) { _, st in
            if st != nil { BetaQA.shared.pass("A-HEALTH-03", note: "Insights showed \(st!.title) with \(model.context?.suggestions.count ?? 0) meal ideas") }
        }
        .onChange(of: model.access) { _, a in
            if a == .denied || a == .unavailable || a == .entitlementMissing { BetaQA.shared.pass("A-HEALTH-05", note: "Graceful \(a) state shown") }
        }
        .task { await model.refresh(recipes: store.recipes); prompt = model.context?.prompts.first; entries = JournalStore.shared.entries() }
    }

    @ViewBuilder private var bodyToday: some View {
        card("Your body today") {
            switch model.access {
            case .unavailable:
                Text("Apple Health isn't available on this device.").accessibilityIdentifier("insights.unavailable")
            case .entitlementMissing:
                Text("This build was signed without Apple Health access. Re-sideload the latest Ate build with the same Apple ID to enable it.")
                    .accessibilityIdentifier("insights.entitlementMissing")
            case .denied:
                Text("Health access is off. Turn it on in Settings › Health › Data Access & Devices › ate.").accessibilityIdentifier("insights.denied")
            case .notDetermined:
                Text("Connect Apple Health (read-only) to get meal ideas that fit your sleep, steps and workouts. Your health data stays on this iPhone.")
                    .font(AteFont.body(14))
                Button("Connect Apple Health") { Task { await model.connect(recipes: store.recipes); prompt = model.context?.prompts.first } }
                    .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("insights.connect")
            case .requested:
                if model.loading { ProgressView() }
                else if let c = model.context {
                    Label(c.insight.state.title, systemImage: c.insight.state.symbol).font(AteFont.display(20))
                        .accessibilityIdentifier("insights.state")
                    Text(c.insight.headline).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                } else {
                    Text("No recent Health data yet. Wear your Apple Watch or carry your iPhone and check back later.")
                        .accessibilityIdentifier("insights.noData")
                }
            }
        }
        .font(AteFont.body(14))
    }

    @ViewBuilder private var journalCard: some View {
        card("Your Ate journal") {
            JournalingSuggestionsButton { m in
                prompt = JournalPrompt(text: m.isWorkout ? "After \(m.title): what would help you recover?" : "About \(m.title): what did you eat, and would you cook it again?",
                                       state: model.context?.insight.state ?? .balanced)
                if m.isWorkout { store.show("Tip: try a high-protein recipe from Suggested meals") }
            }
            if entries.isEmpty {
                Text("No entries yet.").font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            }
            ForEach(entries, id: \.id) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + e.state.title)
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    Text(e.text).font(AteFont.body(14))
                }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("insights.entry")
                .contextMenu { Button("Delete", role: .destructive) { JournalStore.shared.delete(e); entries = JournalStore.shared.entries() } }
            }
        }
    }

    private func save(_ c: HealthContext) {
        let p = prompt ?? c.prompts.first
        if JournalStore.shared.save(prompt: p?.text ?? "", text: draft, state: c.insight.state, recipeIDs: c.suggestions.map(\.recipeID)) {
            draft = ""; entries = JournalStore.shared.entries(); store.show("Saved to your Ate journal")
            BetaQA.shared.pass("A-HEALTH-04", note: "Saved a local journal entry")
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(AteFont.display(18)); c() }
            .frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 20)
    }
}

/// Small "Today" card at the top of the Library (only once Health is connected and has data).
struct TodayHealthCard: View {
    @Environment(AppStore.self) private var store
    @State private var model = InsightsModel.shared
    var body: some View {
        Group {
            if let c = model.context {
                Button { store.tab = .more; store.morePath = [] ; InsightsNavState.shared.open = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: c.insight.state.symbol).font(.system(size: 20)).foregroundStyle(Theme.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today · " + c.insight.state.title).font(AteFont.body(15, .semibold))
                            Text(c.insight.state.mealFocus).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
                    }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("library.todayCard")
            }
        }
        .task { if model.access == .requested && model.context == nil { await model.refresh(recipes: store.recipes) } }
    }
}

@MainActor @Observable final class InsightsNavState { static let shared = InsightsNavState(); var open = false }

struct RecipeSheetTarget: Identifiable, Hashable { let id: String }

/// Recipe opened from Insights: its own stack + Done, so Back never strands you. Cook mode dismisses the sheet
/// first so the root full-screen cover can present.
struct RecipeSheet: View {
    let recipeID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RecipeDetailView(recipeID: recipeID)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(AteFont.body(16, .semibold)).frame(minHeight: 44).padding(.horizontal, 16)
                            .accessibilityIdentifier("recipeSheet.done")
                    }.background(Theme.background)
                }
        }
        .onDisappear { BetaQA.shared.pass("A-HEALTH-08", note: "Opened and closed a suggested recipe") }
        .onChange(of: store.cookTarget) { _, t in
            // Root presents cook mode full-screen; hand off after the sheet is gone.
            guard let t else { return }
            store.cookTarget = nil
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.cookTarget = t }
        }
        .onChange(of: store.path) { _, p in if !p.isEmpty { dismiss() } }
    }
}
