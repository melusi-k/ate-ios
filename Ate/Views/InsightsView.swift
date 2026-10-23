import SwiftUI
import Charts
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor @Observable
final class InsightsModel {
    static let shared = InsightsModel()
    private(set) var health: HealthKitServicing
    var access: HealthAccess
    /// Beta debug picker: swap to a mock scenario ("" = live Apple Health).
    func useScenario(_ s: String, recipes: [RecipeCard]) async {
        UserDefaults.standard.set(s, forKey: HealthServiceFactory.debugKey)
        health = HealthServiceFactory.make(arguments: AppConfig.isUITesting ? ["-qaMockHealth", s] : [])
        if health is MockHealthKitService { _ = await health.requestAccess() }
        await refresh(recipes: recipes)
    }
    var context: HealthContext?
    var loading = false
    /// Loaded once per launch on first appear; pull-to-refresh re-queries.
    private(set) var loadedOnce = false
    /// UI tests (`-qaHealthPrompt`): stand-in for the system Health sheet so a refactor that stops asking is caught.
    var mockPromptShown = false
    init(health: HealthKitServicing) { self.health = health; access = health.access }
    convenience init() { self.init(health: HealthServiceFactory.make()) }

    func loadIfNeeded(recipes: [RecipeCard]) async { guard !loadedOnce else { return }; loadedOnce = true; await refresh(recipes: recipes) }
    func tapConnect(recipes: [RecipeCard]) async {
        if AppConfig.isUITesting && ProcessInfo.processInfo.arguments.contains("-qaHealthPrompt") { mockPromptShown = true; return }
        await connect(recipes: recipes)
    }
    /// Last authorization error, shown under the Health card so a failed request is never silent.
    var requestError: String?
    /// True when Beta testing › Health data is a mock scenario: show a "Sample data" badge, never a red entitlement error.
    var isSample: Bool { health is MockHealthKitService }
    func connect(recipes: [RecipeCard]) async {
        access = await health.requestAccess(); requestError = health.lastError
        await refresh(recipes: recipes)
    }
    func useSampleData(recipes: [RecipeCard]) async { await useScenario("recovery", recipes: recipes) }
    func refresh(recipes: [RecipeCard]) async {
        access = health.access
        guard access == .requested else { context = nil; return }
        loading = true; defer { loading = false }
        let s = await health.summary(days: 7)
        guard let i = HealthInsightEngine.insight(for: s) else { context = nil; return }
        if WidgetBridge.lastHealthState != i.state {
            WidgetBridge.lastHealthState = i.state
            if let st = AppStore.current { WidgetBridge.publish(st, delay: 0) }
        }
        context = HealthContext(summary: s, insight: i,
                                suggestions: RecipeHealthMatcher.suggestions(for: i.state, recipes: recipes),
                                prompts: await JournalSuggestionService.prompts(for: i))
    }
}


/// Minimal, privacy-conscious snapshot used for recipe/progress insights. It contains no Health data.
enum InsightsTileOrder {
    static let defaults = ["tracker", "recipeProgress", "bodyToday", "suggestedMeals", "dailyReflection", "journal"]

    static func resolve(_ stored: String) -> [String] {
        let known = Set(defaults)
        var seen = Set<String>()
        let saved = stored.split(separator: ",").map(String.init).filter { known.contains($0) && seen.insert($0).inserted }
        return saved + defaults.filter { seen.insert($0).inserted }
    }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }

    static func moving(_ ids: [String], id: String, before target: String) -> [String] {
        guard id != target, let sourceIndex = ids.firstIndex(of: id), ids.contains(target) else { return ids }
        var result = ids
        result.remove(at: sourceIndex)
        guard let newTargetIndex = result.firstIndex(of: target) else { return ids }
        result.insert(id, at: newTargetIndex)
        return result
    }

    static func moving(_ ids: [String], id: String, offset: Int) -> [String] {
        guard let sourceIndex = ids.firstIndex(of: id) else { return ids }
        let targetIndex = sourceIndex + offset
        guard ids.indices.contains(targetIndex) else { return ids }
        var result = ids
        result.swapAt(sourceIndex, targetIndex)
        return result
    }
}

struct RecipeProgressInsightInput: Equatable {
    var savedRecipeCount: Int
    var cookedRecipeCount: Int
    var cookingDayCount: Int
    var mostCookedRecipe: String?
    var recipeTitles: [String]
    var duplicateTitleGroups: [[String]] = []

    var hasEnoughData: Bool { savedRecipeCount >= 3 || cookedRecipeCount >= 2 || cookingDayCount >= 2 }

    static func make(recipes: [RecipeCard], historyEvents: [String: Set<String>]) -> RecipeProgressInsightInput {
        let ids = Set(recipes.map(\.id))
        let events = historyEvents.filter { !$0.value.isEmpty }
        var counts: [String: Int] = [:]
        for recipeIDs in events.values {
            for id in recipeIDs where ids.contains(id) { counts[id, default: 0] += 1 }
        }
        let titleByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) })
        let mostCookedID = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? (titleByID[lhs.key] ?? "") < (titleByID[rhs.key] ?? "") : lhs.value > rhs.value
        }.first?.key
        return RecipeProgressInsightInput(
            savedRecipeCount: recipes.count,
            cookedRecipeCount: counts.keys.count,
            cookingDayCount: events.filter { !$0.value.intersection(ids).isEmpty }.count,
            mostCookedRecipe: mostCookedID.flatMap { titleByID[$0] },
            recipeTitles: Array(recipes.map(\.title).filter { !$0.isEmpty }.prefix(5)),
            duplicateTitleGroups: Dictionary(grouping: recipes.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            }.values.filter { $0.count > 1 }.map { $0.map(\.title) }.sorted { ($0.first ?? "") < ($1.first ?? "") }
        )
    }
}

struct RecipeProgressInsight: Equatable {
    var title: String
    var detail: String
    var evidence: String
    var generated: Bool
}

enum RecipeProgressInsightService {
    static func fallback(for input: RecipeProgressInsightInput) -> RecipeProgressInsight? {
        guard input.hasEnoughData else { return nil }
        if let duplicateGroup = input.duplicateTitleGroups.first {
            let titles = duplicateGroup.joined(separator: "” and “")
            return RecipeProgressInsight(
                title: "Possible overlapping recipe entries",
                detail: "You have saved recipes with the same title: “\(titles)”. They may be separate versions, so review them before making changes.",
                evidence: "Based on titles in your saved recipe collection.",
                generated: false
            )
        }
        if input.cookedRecipeCount > 0 {
            let focus = input.mostCookedRecipe.map { " You could revisit \"\($0)\" or try another recipe from your collection." } ?? " Try another recipe from your collection."
            return RecipeProgressInsight(
                title: "Your cooking rhythm",
                detail: "You've cooked \(input.cookedRecipeCount) saved recipe\(input.cookedRecipeCount == 1 ? "" : "s") across \(input.cookingDayCount) day\(input.cookingDayCount == 1 ? "" : "s").\(focus)",
                evidence: "Based on your saved recipes and cooking history.",
                generated: false
            )
        }
        return RecipeProgressInsight(
            title: "Your recipe collection is taking shape",
            detail: "You have \(input.savedRecipeCount) saved recipes. As you cook and record a few, Ate can surface patterns and ideas to revisit.",
            evidence: "Based on your saved recipe collection.",
            generated: false
        )
    }

    static func insight(for input: RecipeProgressInsightInput, useModel: Bool = OnDeviceBackend.isModelAvailable && !AppConfig.isUITesting) async -> RecipeProgressInsight? {
        guard let fallback = fallback(for: input) else { return nil }
        // Duplicate candidates are deterministic and need a precise review action; do not paraphrase them with a model.
        if !input.duplicateTitleGroups.isEmpty { return fallback }
        guard useModel else { return fallback }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
            You write one brief, warm, non-judgmental cooking-app reflection.
            Use only facts explicitly supplied in the user's compact recipe summary.
            Do not infer health, nutrition, skill, motivation, or emotions. No medical advice.
            One or two short sentences, advisory only, no invented numbers or claims.
            """)
            let titles = input.recipeTitles.joined(separator: ", ")
            let prompt = "Saved recipes: \(input.savedRecipeCount). Distinct saved recipes cooked: \(input.cookedRecipeCount). Cooking days: \(input.cookingDayCount). Most cooked saved recipe: \(input.mostCookedRecipe ?? "not recorded"). Recipe titles (up to five): \(titles). Write a reflection."
            if let response = try? await session.respond(to: prompt) {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if (12...360).contains(text.count) {
                    return RecipeProgressInsight(title: fallback.title, detail: text, evidence: fallback.evidence, generated: true)
                }
            }
        }
        #endif
        return fallback
    }
}

/// More → Insights: "Your body today", "Suggested meals", "Reflect on your day", "Save to journal".
struct InsightsView: View {
    var screenTitle: String = "Insights"
    @Environment(AppStore.self) private var store
    @State private var model = InsightsModel.shared
    @State private var draft = ""
    @State private var prompt: JournalPrompt?
    @State private var entries: [JournalEntry] = []
    @State private var recipeProgressInsight: RecipeProgressInsight?
    @State private var recipeProgressLoading = false
    @State private var isEditingInsightOrder = false
    @AppStorage("insights.tileOrder") private var savedInsightTileOrder = ""
    @State private var openRecipe: RecipeSheetTarget?
    @State private var pendingMoment: (title: String, date: Date?)?
    @AppStorage(JournalingSuggestionsGate.settingKey) private var journalingEnabled = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your insights").font(AteFont.display(18))
                        Spacer()
                        Button(isEditingInsightOrder ? "Done" : "Edit") {
                            withAnimation(.snappy) { isEditingInsightOrder.toggle() }
                        }
                        .font(AteFont.body(14, .semibold))
                        .accessibilityIdentifier("insights.order.edit")
                    }
                    if isEditingInsightOrder {
                        Text("Drag a tile to move it, or use the arrows to change its position.")
                            .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    }
                    ForEach(orderedInsightTileIDs, id: \.self) { tileID in
                        VStack(spacing: 8) {
                            if isEditingInsightOrder {
                                HStack(spacing: 12) {
                                    Label("Reorder tile", systemImage: "line.3.horizontal")
                                        .font(AteFont.body(12, .semibold))
                                        .foregroundStyle(Theme.mutedForeground)
                                    Spacer()
                                    Button { moveInsightTile(tileID, offset: -1) } label: {
                                        Image(systemName: "arrow.up").frame(width: 36, height: 36)
                                    }
                                    .disabled(orderedInsightTileIDs.first == tileID)
                                    .accessibilityLabel("Move \(insightTileTitle(tileID)) up")
                                    Button { moveInsightTile(tileID, offset: 1) } label: {
                                        Image(systemName: "arrow.down").frame(width: 36, height: 36)
                                    }
                                    .disabled(orderedInsightTileIDs.last == tileID)
                                    .accessibilityLabel("Move \(insightTileTitle(tileID)) down")
                                }
                            }
                            insightTile(tileID)
                        }
                        .draggable(tileID)
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first, source != tileID else { return false }
                            moveInsightTile(source, before: tileID)
                            return true
                        }
                        .accessibilityIdentifier("insights.tile.\(tileID)")
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .pageWidth()
            }
        }
        .navigationTitle(screenTitle)
        .ateRootNavigationChrome(logoID: "insights.logo")
        .sheet(item: $openRecipe) { t in RecipeSheet(recipeID: t.id).environment(store) }
        .onChange(of: model.context?.insight.state) { _, st in
            if st != nil { BetaQA.shared.pass("A-HEALTH-03", note: "Insights showed \(st!.title) with \(model.context?.suggestions.count ?? 0) meal ideas") }
        }
        .onChange(of: model.access) { _, a in
            if a == .denied || a == .unavailable || a == .entitlementMissing { BetaQA.shared.pass("A-HEALTH-05", note: "Graceful \(a) state shown") }
        }
        .refreshable { await model.refresh(recipes: store.recipes); prompt = model.context?.prompts.first; await refreshRecipeProgressInsight() }
        .task { await model.loadIfNeeded(recipes: store.recipes); prompt = prompt ?? model.context?.prompts.first; entries = JournalStore.shared.entries(); await refreshRecipeProgressInsight() }
        .onAppear { entries = JournalStore.shared.entries() }
        .alert("“ate” would like to access your Health data", isPresented: $model.mockPromptShown) {
            Button("Don't Allow", role: .cancel) {}
            Button("Allow") { Task { await model.connect(recipes: store.recipes); prompt = model.context?.prompts.first } }
        } message: { Text("Read: Sleep, Steps, Active Energy, Workouts") }
    }


    private var orderedInsightTileIDs: [String] { InsightsTileOrder.resolve(savedInsightTileOrder) }

    private func insightTileTitle(_ id: String) -> String {
        switch id {
        case "tracker": return "Cooking tracker"
        case "recipeProgress": return "Recipe & cooking insights"
        case "bodyToday": return "Your body today"
        case "suggestedMeals": return "Suggested meals"
        case "dailyReflection": return "Reflect on your day"
        default: return "Your Ate journal"
        }
    }

    private func moveInsightTile(_ id: String, before target: String) {
        savedInsightTileOrder = InsightsTileOrder.encode(InsightsTileOrder.moving(orderedInsightTileIDs, id: id, before: target))
    }

    private func moveInsightTile(_ id: String, offset: Int) {
        savedInsightTileOrder = InsightsTileOrder.encode(InsightsTileOrder.moving(orderedInsightTileIDs, id: id, offset: offset))
    }

    @ViewBuilder private func insightTile(_ id: String) -> some View {
        switch id {
        case "tracker":
            CookingTrackerView()
        case "recipeProgress":
            recipeProgressCard
        case "bodyToday":
            bodyToday
        case "suggestedMeals":
            suggestedMealsCard
        case "dailyReflection":
            dailyReflectionCard
        case "journal":
            journalCard
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var suggestedMealsCard: some View {
        if let c = model.context {
            card("Suggested meals") {
                Text(c.insight.state.mealFocus).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                if c.suggestions.isEmpty {
                    Text("Save a few recipes and Ate will pick the ones that fit your day.")
                        .font(AteFont.body(14)).accessibilityIdentifier("insights.noSuggestions")
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
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var dailyReflectionCard: some View {
        if let c = model.context {
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
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var recipeProgressCard: some View {
        card("Recipe & cooking insights") {
            if recipeProgressLoading {
                ProgressView("Looking at your recipe collection…")
                    .accessibilityIdentifier("insights.progress.loading")
            } else if let insight = recipeProgressInsight {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(insight.title).font(AteFont.body(15, .semibold))
                        Text(insight.detail).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                        Text(insight.evidence + (insight.generated ? " · On-device suggestion" : " · Guided by your saved data"))
                            .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insights.progress.result")
            } else {
                ContentUnavailableView {
                    Label("Your insights are taking shape", systemImage: "sparkles")
                } description: {
                    Text("Save at least three recipes, or cook and record a couple of recipes. Ate will use your collection and cooking history to suggest patterns and ideas to revisit.")
                } actions: {
                    Button("Explore recipes") { store.select(.library) }
                        .buttonStyle(.ate(.secondary, full: true))
                        .accessibilityIdentifier("insights.progress.exploreRecipes")
                }
                .accessibilityIdentifier("insights.progress.empty")
            }
            if recipeProgressInsight?.title == "Possible overlapping recipe entries" {
                Button("Review recipes") { store.select(.library) }
                    .font(AteFont.body(13, .semibold))
                    .accessibilityIdentifier("insights.progress.reviewRecipes")
            }
            Button("Refresh insights") { Task { await refreshRecipeProgressInsight() } }
                .font(AteFont.body(13, .semibold))
                .accessibilityIdentifier("insights.progress.refresh")
        }
    }

    @MainActor private func refreshRecipeProgressInsight() async {
        recipeProgressLoading = true
        defer { recipeProgressLoading = false }
        let input = RecipeProgressInsightInput.make(recipes: store.recipes, historyEvents: CookingHistory.shared.events)
        recipeProgressInsight = await RecipeProgressInsightService.insight(for: input)
    }

    @ViewBuilder private var bodyToday: some View {
        card("Your body today") {
            if model.isSample {
                Label("Sample data", systemImage: "testtube.2").font(AteFont.body(12, .semibold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primary.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("insights.sampleBadge")
            } else if let err = model.requestError {
                Label("Apple Health request failed: \(err)", systemImage: "exclamationmark.triangle")
                    .font(AteFont.body(13)).foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("insights.healthError")
            }
            switch model.access {
            case .unavailable:
                unavailable("Apple Health isn't available", "heart.slash", "This device has no Health app (e.g. iPad).", id: "insights.unavailable")
            case .entitlementMissing:
                unavailable("Health access not in this build", "lock.shield",
                            "This copy was signed without Apple Health access. Re-sideload the latest Ate build with the same Apple ID.", id: "insights.entitlementMissing")
            case .denied:
                unavailable("Health access is off", "hand.raised", "Turn it on in Settings › Health › Data Access & Devices › ate.", id: "insights.denied", settings: true, retry: true)
            case .notDetermined:
                Text("Connect Apple Health (read-only) to get meal ideas that fit your sleep, steps and workouts. Your health data stays on this iPhone.")
                    .font(AteFont.body(14))
                Button("Connect Apple Health") { Task { await model.tapConnect(recipes: store.recipes); prompt = model.context?.prompts.first } }
                    .buttonStyle(.ate(.primary, full: true)).accessibilityIdentifier("insights.connect")
            case .requested:
                if model.loading { ProgressView() }
                else if let c = model.context {
                    Label(c.insight.state.title, systemImage: c.insight.state.symbol).font(AteFont.display(20))
                        .accessibilityIdentifier("insights.state")
                    Text(c.insight.headline).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                    StepsSparkline(days: c.summary.days)
                } else {
                    unavailable("No recent Health data", "chart.line.downtrend.xyaxis",
                                "Wear your Apple Watch or carry your iPhone, then pull to refresh.", id: "insights.noData", retry: true)
                }
            }
        }
        .font(AteFont.body(14))
    }

    @ViewBuilder private var journalCard: some View {
        card("Your Ate journal") {
            if journalingEnabled && JournalingSuggestionsGate.isAvailable && !AppConfig.isUITesting {
                JournalingSuggestionsButton { m in handle(moment: m) }
            }
            if entries.isEmpty {
                Text("No entries yet.").font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            }
            ForEach(entries.prefix(5), id: \.id) { e in
                NavigationLink { JournalEntryDetailView(entryID: e.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + e.state.title)
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    if let line = JournalingMomentMapper.contextLine(title: e.journalingSuggestionTitle, date: e.momentDate) {
                        Label(line, systemImage: "book.pages").font(AteFont.body(12)).foregroundStyle(Theme.primary)
                            .accessibilityIdentifier("insights.entryMomentContext")
                    }
                    Text(e.text).font(AteFont.body(14)).lineLimit(3).multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("insights.entry")
                .contextMenu { Button("Delete", role: .destructive) { JournalStore.shared.delete(e); entries = JournalStore.shared.entries() } }
            }
            if entries.count > 5 {
                NavigationLink(value: Route.journal) { Text("See all \(entries.count) entries").font(AteFont.body(14, .semibold)) }
                    .accessibilityIdentifier("insights.allEntries")
            }
        }
    }

    @ViewBuilder
    private func unavailable(_ title: String, _ symbol: String, _ detail: String, id: String, settings: Bool = false, retry: Bool = false) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: { Text(detail) } actions: {
            if settings, let u = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(u) }.accessibilityIdentifier("insights.openSettings")
            }
            if retry { Button("Try again") { Task { await model.refresh(recipes: store.recipes) } }.accessibilityIdentifier("insights.retry") }
            if !AppConfig.channel.isEmpty || AppConfig.isUITesting {
                Button("Use sample data") { Task { await model.useSampleData(recipes: store.recipes); prompt = model.context?.prompts.first } }
                    .accessibilityIdentifier("insights.sampleData")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    private func handle(moment m: PickedMoment) {
        switch JournalingMomentMapper.map(title: m.title, date: m.date.map { DateInterval(start: $0, duration: 0) }, hasPhotos: !m.photoURLs.isEmpty, isWorkout: m.isWorkout) {
        case .recipeDraft(let title, let date):
            let card = JournalingMomentMapper.draft(title: title, date: date)
            store.add(card); openRecipe = RecipeSheetTarget(id: card.id); store.show("Recipe draft from your Journal moment")
        case .journalEntry(let p, let title, let date, let state):
            prompt = JournalPrompt(text: p, state: state); pendingMoment = (title, date)
        }
    }

    private func save(_ c: HealthContext) {
        let p = prompt ?? c.prompts.first
        let moment = pendingMoment; pendingMoment = nil
        if JournalStore.shared.save(prompt: p?.text ?? "", text: draft, state: c.insight.state, recipeIDs: c.suggestions.map(\.recipeID),
                                    momentTitle: moment?.title, momentDate: moment?.date) {
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
                Button { store.select(.library); InsightsNavState.shared.open = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: c.insight.state.symbol).font(.title3).foregroundStyle(Theme.primary)
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
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("recipeSheet.done")
                    }
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

/// 7-day steps sparkline (Swift Charts). Hidden when there are fewer than 2 days of steps.
struct StepsSparkline: View {
    let days: [HealthDay]
    var body: some View {
        let pts: [StepPoint] = days.compactMap { d in d.steps.map { StepPoint(date: d.date, steps: $0) } }
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Steps, last \(pts.count) days").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    if let today = pts.last { Text("Today \(today.steps.formatted())").font(AteFont.body(12, .semibold)).monospacedDigit()
                        .accessibilityIdentifier("insights.stepsToday") }
                }
                Chart(pts) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Steps", p.steps)).interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Day", p.date, unit: .day), y: .value("Steps", p.steps)).foregroundStyle(Theme.primary.opacity(0.15))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { v in
                        AxisGridLine()
                        AxisValueLabel { if let n = v.as(Int.self) { Text(n >= 1000 ? "\(n / 1000)k" : "\(n)") } }
                    }
                }
                .foregroundStyle(Theme.primary).frame(height: 84)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Steps trend over \(pts.count) days, today \(pts.last?.steps.formatted() ?? "no data") steps")
            .accessibilityIdentifier("insights.sparkline")
        }
    }
}

struct StepPoint: Identifiable { let date: Date; let steps: Int; var id: Date { date } }
