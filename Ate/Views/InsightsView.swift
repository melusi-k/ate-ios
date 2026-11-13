import SwiftUI
import Charts
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor @Observable
final class InsightsModel {
    static let shared = InsightsModel()
    private(set) var health: HealthKitServicing
    @ObservationIgnored private var refreshGeneration = UUID()
    @ObservationIgnored private let makePrompts: @MainActor (HealthInsight) async -> [JournalPrompt]
    @ObservationIgnored private let publishHealthState: @MainActor (HealthState) -> Void
    private func invalidateRefresh() {
        refreshGeneration = UUID()
        loading = false
        context = nil
    }
    var access: HealthAccess
    /// Beta debug picker: swap to a mock scenario ("" = live Apple Health).
    func useScenario(_ s: String, recipes: [RecipeCard]) async {
        invalidateRefresh()
        UserDefaults.standard.set(s, forKey: HealthServiceFactory.debugKey)
        health = HealthServiceFactory.make(arguments: AppConfig.isUITesting ? ["-qaMockHealth", s] : [])
        let generation = refreshGeneration
        let source = health
        if source is MockHealthKitService { _ = await source.requestAccess() }
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        await refresh(recipes: recipes)
    }
    var context: HealthContext?
    var loading = false
    /// Loaded once per launch on first appear; pull-to-refresh re-queries.
    private(set) var loadedOnce = false
    /// UI tests (`-qaHealthPrompt`): stand-in for the system Health sheet so a refactor that stops asking is caught.
    var mockPromptShown = false
    init(health: HealthKitServicing,
         makePrompts: @escaping @MainActor (HealthInsight) async -> [JournalPrompt] = { await JournalSuggestionService.prompts(for: $0) },
         publishHealthState: @escaping @MainActor (HealthState) -> Void = { state in
             if WidgetBridge.lastHealthState != state {
                 WidgetBridge.lastHealthState = state
                 if let store = AppStore.current { WidgetBridge.publish(store, delay: 0) }
             }
         }) {
        self.health = health; access = health.access
        self.makePrompts = makePrompts; self.publishHealthState = publishHealthState
    }
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
        invalidateRefresh()
        let generation = refreshGeneration
        let source = health
        let requestedAccess = await source.requestAccess()
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        access = requestedAccess; requestError = source.lastError
        await refresh(recipes: recipes)
    }
    func useSampleData(recipes: [RecipeCard]) async { await useScenario("recovery", recipes: recipes) }
    func refresh(recipes: [RecipeCard]) async {
        let generation = UUID(); refreshGeneration = generation
        let source = health
        access = source.access
        guard access == .requested, !Task.isCancelled else {
            context = nil; loading = false; return
        }
        loading = true
        defer { if generation == refreshGeneration { loading = false } }
        let summary = await source.summary(days: 7)
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        access = source.access
        guard access == .requested else { context = nil; return }
        guard let insight = HealthInsightEngine.insight(for: summary) else { context = nil; return }
        let prompts = await makePrompts(insight)
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        access = source.access
        guard access == .requested else { context = nil; return }
        // Single synchronous publication after BOTH await boundaries. Stale summary
        // or wording may neither replace context nor publish a widget state.
        context = HealthContext(summary: summary, insight: insight,
            suggestions: RecipeHealthMatcher.suggestions(for: insight.state, recipes: recipes), prompts: prompts)
        publishHealthState(insight.state)
    }
}


/// Minimal, privacy-conscious snapshot used for recipe/progress insights. It contains no Health data.
enum InsightsTileOrder {
    static let defaults = ["tracker", "recipeProgress", "bodyToday", "suggestedMeals", "dailyReflection"]

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
    var recordedMealsThisWeek: Int = 0
    var firstTimeRecipesThisWeek: Int = 0
    var currentStreak: Int = 0
    /// Saved recipes recorded in cooking history this week, most cooked first (audit: tie patterns back to their recipes).
    /// Presentation-only: never part of any evidence fingerprint, so linking cannot reset lifecycle state.
    var weekRecipeRefs: [RecipeReference] = []
    /// Saved recipes cooked for the first time this week.
    var firstTimeRecipeRefs: [RecipeReference] = []
    /// Identity behind `mostCookedRecipe`, so an insight can link to the actual recipe.
    var mostCookedRecipeID: String? = nil

    var hasEnoughData: Bool { !duplicateTitleGroups.isEmpty || savedRecipeCount >= 3 || cookedRecipeCount >= 2 || cookingDayCount >= 2 }

    /// Most cooked first, titles breaking ties, so the shown recipes are stable and relevant.
    static func recipeReferences(for ids: some Sequence<String>, counts: [String: Int], titleByID: [String: String], limit: Int) -> [RecipeReference] {
        ids.compactMap { id in titleByID[id].map { RecipeReference(id: id, title: $0) } }
            .sorted { lhs, rhs in
                let l = counts[lhs.id] ?? 0, r = counts[rhs.id] ?? 0
                if l != r { return l > r }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
            .prefix(max(0, limit)).map { $0 }
    }

    static func make(recipes: [RecipeCard], historyEvents: [String: Set<String>], calendar: Calendar = .autoupdatingCurrent, now: Date = Date(), history: CookingHistory = .shared) -> RecipeProgressInsightInput {
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
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekKeys = Set(events.keys.filter { key in
            guard let date = history.date(for: key), let week else { return false }
            return week.contains(date)
        })
        let weekIDs = weekKeys.reduce(into: Set<String>()) { $0.formUnion(events[$1] ?? []) }.intersection(ids)
        let firstTimeIDs = weekIDs.filter { id in
            !events.contains { key, values in
                guard values.contains(id), let date = history.date(for: key), let week else { return false }
                return date < week.start
            }
        }
        let weekMeals = weekKeys.reduce(0) { $0 + (events[$1]?.intersection(ids).count ?? 0) }
        let duplicateGroups = Dictionary(grouping: recipes.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        }.values.filter { $0.count > 1 }.map { $0.map(\.title) }.sorted { ($0.first ?? "") < ($1.first ?? "") }
        return RecipeProgressInsightInput(
            savedRecipeCount: recipes.count,
            cookedRecipeCount: counts.keys.count,
            cookingDayCount: events.filter { !$0.value.intersection(ids).isEmpty }.count,
            mostCookedRecipe: mostCookedID.flatMap { titleByID[$0] },
            recipeTitles: Array(recipes.map(\.title).filter { !$0.isEmpty }.prefix(5)),
            duplicateTitleGroups: duplicateGroups,
            recordedMealsThisWeek: weekMeals,
            firstTimeRecipesThisWeek: firstTimeIDs.count,
            currentStreak: history.streak(from: events, asOf: now),
            weekRecipeRefs: recipeReferences(for: weekIDs, counts: counts, titleByID: titleByID, limit: 3),
            firstTimeRecipeRefs: recipeReferences(for: firstTimeIDs, counts: counts, titleByID: titleByID, limit: 3),
            mostCookedRecipeID: mostCookedID
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
    static func candidates(
        for input: RecipeProgressInsightInput,
        shoppingItems: [ShoppingItem] = [],
        nutritionEntries: [NutritionDiaryEntry]? = nil,
        isEligible: (RankedRecipeInsightCandidate) -> Bool = { _ in true }
    ) -> [RankedRecipeInsightCandidate] {
        InsightCandidateEngine.candidates(for: input, shoppingItems: shoppingItems, nutritionEntries: nutritionEntries, isEligible: isEligible)
    }

    static func fallback(for input: RecipeProgressInsightInput) -> RecipeProgressInsight? {
        if let duplicateGroup = input.duplicateTitleGroups.first {
            let titles = duplicateGroup.joined(separator: "” and “")
            return RecipeProgressInsight(
                title: "Possible overlapping recipe entries",
                detail: "You have saved recipes with the same title: “\(titles)”. They may be separate versions, so review them before making changes.",
                evidence: "Based on titles in your saved recipe collection.",
                generated: false
            )
        }
        guard input.hasEnoughData else { return nil }
        if input.cookedRecipeCount > 0 {
            var observations: [String] = []
            if input.recordedMealsThisWeek > 0 {
                observations.append("You've recorded \(input.recordedMealsThisWeek) cooked meal\(input.recordedMealsThisWeek == 1 ? "" : "s") this week")
            }
            if input.firstTimeRecipesThisWeek > 0 {
                observations.append("\(input.firstTimeRecipesThisWeek) saved recipe\(input.firstTimeRecipesThisWeek == 1 ? "" : "s") appear in your cooking history for the first time")
            }
            if input.currentStreak > 1 {
                observations.append("your recorded cooking streak is \(input.currentStreak) days")
            }
            if observations.count >= 2 {
                return RecipeProgressInsight(
                    title: "You're building a steady rhythm",
                    detail: observations.joined(separator: ", and ") + ". You could revisit a meal, try another saved recipe, or reflect on what worked for you this week—whatever feels useful.",
                    evidence: "Based on your saved recipes and recorded cooking history.",
                    generated: false
                )
            }
            let focus = input.mostCookedRecipe.map { " You could revisit “\($0)” or try another recipe from your collection." } ?? " Try another recipe from your collection."
            return RecipeProgressInsight(
                title: "Your cooking rhythm",
                detail: "You've cooked \(input.cookedRecipeCount) distinct saved recipe\(input.cookedRecipeCount == 1 ? "" : "s") across \(input.cookingDayCount) recorded day\(input.cookingDayCount == 1 ? "" : "s").\(focus)",
                evidence: "Based on your saved recipes and recorded cooking history.",
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
    /// False for the named Journal hub route; true retains the generic presentation behavior.
    var isRoot: Bool = true
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model = InsightsModel.shared
    @State private var recipeProgressCandidates: [RankedRecipeInsightCandidate] = []
    @State private var recipeProgressSuppressed = false
    @State private var recipeProgressLoading = false
    @State private var recipeProgressEvidenceFingerprint: String?
    @State private var recipeProgressRefreshGeneration = 0
    @State private var cookingHistoryScrollRequest = 0
    @State private var isEditingInsightOrder = false
    @AppStorage("insights.tileOrder") private var savedInsightTileOrder = ""
    @State private var openRecipe: RecipeSheetTarget?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your insights").font(AteFont.display(18))
                            // UITesting-only diagnostics on an existing element: no geometry change,
                            // state categories only (never raw error text), lands in failure hierarchies.
                            .accessibilityValue(AppConfig.isUITesting ? "qa access=\(String(describing: model.access)) context=\(model.context == nil ? "nil" : "loaded") sample=\(model.isSample) errPresent=\(model.requestError == nil ? "no" : "yes")" : "")
                        Spacer()
                        Button { Task { await refreshAllInsights() } } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .font(AteFont.body(13, .semibold))
                        .disabled(model.loading || recipeProgressLoading)
                        .accessibilityIdentifier("insights.refresh")
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
                    ForEach(visibleInsightTileIDs, id: \.self) { tileID in
                        VStack(spacing: 8) {
                            if isEditingInsightOrder {
                                HStack(spacing: 12) {
                                    Label("Reorder tile", systemImage: "line.3.horizontal")
                                        .font(AteFont.body(12, .semibold))
                                        .foregroundStyle(Theme.mutedForeground)
                                    Spacer()
                                    Button { moveVisibleInsightTile(tileID, offset: -1) } label: {
                                        Image(systemName: "arrow.up").frame(width: 36, height: 36)
                                    }
                                    .disabled(visibleInsightTileIDs.first == tileID)
                                    .accessibilityLabel("Move \(insightTileTitle(tileID)) up")
                                    Button { moveVisibleInsightTile(tileID, offset: 1) } label: {
                                        Image(systemName: "arrow.down").frame(width: 36, height: 36)
                                    }
                                    .disabled(visibleInsightTileIDs.last == tileID)
                                    .accessibilityLabel("Move \(insightTileTitle(tileID)) down")
                                }
                            }
                            insightTile(tileID)
                        }
                        .draggable(isEditingInsightOrder ? tileID : "")
                        .dropDestination(for: String.self) { items, _ in
                            guard isEditingInsightOrder, let source = items.first, source != tileID, !source.isEmpty else { return false }
                            moveInsightTile(source, before: tileID)
                            return true
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("insights.tile.\(tileID)")
                        .id(tileID)
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .pageWidth()
            }
            .onChange(of: cookingHistoryScrollRequest) { _, _ in
                // This action can originate below the calendar in the same pushed hub.
                // Reveal the real tracker tile instead of dismissing the current route.
                withAnimation(Motion.anim(.snappy)) { scrollProxy.scrollTo("tracker", anchor: .top) }
            }
            }
        }
        // The tab bar's floating bottom accessory can overlap trailing scroll content;
        // match SettingsView and leave room for it.
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle(screenTitle)
        .ateRootNavigationChrome(logoID: "insights.logo", enabled: isRoot)
        .sheet(item: $openRecipe) { t in RecipeSheet(recipeID: t.id, recordsHealthSuggestionEvidence: t.recordsHealthSuggestionEvidence).environment(store) }
        .onChange(of: model.context?.insight.state) { _, st in
            if st != nil { BetaQA.shared.pass("A-HEALTH-03", note: "Insights showed \(st!.title) with \(model.context?.suggestions.count ?? 0) meal ideas") }
        }
        .onChange(of: model.access) { _, a in
            if a == .denied || a == .unavailable || a == .entitlementMissing { BetaQA.shared.pass("A-HEALTH-05", note: "Graceful \(a) state shown") }
        }
        .refreshable { await refreshAllInsights() }
        .task {
            // Local cooking-history insights must not wait for unrelated HealthKit queries.
            async let healthLoad: Void = model.loadIfNeeded(recipes: store.recipes)
            await refreshRecipeProgressInsight()
            await healthLoad
        }
        .alert("“ate” would like to access your Health data", isPresented: $model.mockPromptShown) {
            Button("Don't Allow", role: .cancel) {}
            Button("Allow") { Task { await model.connect(recipes: store.recipes) } }
        } message: { Text("Read: Sleep, Steps, Active Energy, Workouts") }
    }


    private var orderedInsightTileIDs: [String] { InsightsTileOrder.resolve(savedInsightTileOrder) }
    private var visibleInsightTileIDs: [String] {
        orderedInsightTileIDs.filter {
            $0 != "dailyReflection" && ( $0 != "suggestedMeals" || model.context != nil )
                && !( $0 == "recipeProgress" && recipeProgressSuppressed )
        }
    }

    private func insightTileTitle(_ id: String) -> String {
        switch id {
        case "tracker": return "Cooking tracker"
        case "recipeProgress": return "Recipe & cooking insights"
        case "bodyToday": return "Your body today"
        case "suggestedMeals": return "Suggested meals"
        case "dailyReflection": return "Reflect on your day"
        default: return "Insights"
        }
    }

    private func moveInsightTile(_ id: String, before target: String) {
        var visible = visibleInsightTileIDs
        guard id != target, let source = visible.firstIndex(of: id), visible.contains(target) else { return }
        visible.remove(at: source)
        guard let destination = visible.firstIndex(of: target) else { return }
        visible.insert(id, at: destination)
        persistVisibleOrder(visible)
    }

    private func moveVisibleInsightTile(_ id: String, offset: Int) {
        var visible = visibleInsightTileIDs
        guard let source = visible.firstIndex(of: id), visible.indices.contains(source + offset) else { return }
        visible.swapAt(source, source + offset)
        persistVisibleOrder(visible)
    }

    private func persistVisibleOrder(_ visible: [String]) {
        var full = orderedInsightTileIDs
        let slots = full.indices.filter { visible.contains(full[$0]) }
        for (slot, id) in zip(slots, visible) { full[slot] = id }
        savedInsightTileOrder = InsightsTileOrder.encode(full)
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
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var suggestedMealsCard: some View {
        if let c = model.context {
            card("Suggested meals") {
                if InsightsSampleMarking.requiresSampleBadge(tileID: "suggestedMeals", isSample: model.isSample) {
                    sampleBadge(id: "insights.sampleBadge.suggestedMeals")
                }
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

    @ViewBuilder private var recipeProgressCard: some View {
        card("Recipe & cooking insights") {
            if recipeProgressLoading {
                ProgressView("Looking at your recipe collection…")
                    .accessibilityIdentifier("insights.progress.loading")
            } else if !recipeProgressCandidates.isEmpty {
                ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recipeProgressCandidates, id: \.id) { candidate in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: recipeProgressInsightSymbol(for: candidate.insight))
                                    .foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.insight.title).font(AteFont.body(15, .semibold))
                                    Text(candidate.insight.detail).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                                    Text(candidate.insight.evidence + " · Guided by your saved data")
                                        .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                                    Text("Evidence: \(candidate.evidenceMetadata.source) · \(candidate.evidenceMetadata.period) · Confidence: \(candidate.evidenceMetadata.confidence.rawValue)")
                                        .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                                        .accessibilityIdentifier("insights.progress.evidence.\(candidate.id)")
                                }
                            }
                            Button {
                                openInsightDestination(for: candidate)
                                markRecipeInsightSeen(candidate)
                            } label: {
                                insightActionLabel(insightActionTitle(for: candidate), symbol: insightActionSymbol(for: candidate))
                            }
                            .accessibilityIdentifier("insights.progress.action.\(candidate.id)")
                            if !candidate.relatedRecipes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("From your cooking history")
                                        .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                                    ForEach(candidate.relatedRecipes, id: \.id) { ref in
                                        Button { openRecipe = RecipeSheetTarget(id: ref.id, recordsHealthSuggestionEvidence: false) } label: {
                                            Label(ref.title, systemImage: "fork.knife")
                                                .font(AteFont.body(13, .semibold))
                                                .foregroundStyle(Theme.primary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("insights.progress.recipe.\(candidate.id).\(ref.id)")
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Button("I've handled this") { resolveRecipeInsight(candidate) }
                                    .font(AteFont.body(12, .semibold))
                                    .accessibilityIdentifier("insights.progress.resolve.\(candidate.id)")
                                Button("Not useful") { dismissRecipeInsight(candidate) }
                                    .font(AteFont.body(12, .semibold))
                                    .accessibilityIdentifier("insights.progress.dismiss.\(candidate.id)")
                                Button("Remind me tomorrow") { snoozeRecipeInsight(candidate) }
                                    .font(AteFont.body(12, .semibold))
                                    .accessibilityIdentifier("insights.progress.snooze.\(candidate.id)")
                            }
                            .foregroundStyle(Theme.mutedForeground)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("insights.progress.candidate.\(candidate.id)")
                        .padding(12)
                        .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("insights.progress.results")
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
        }
    }

    private func insightActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(AteFont.body(15, .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 24)
            Text(title)
                .font(AteFont.body(14, .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(AteFont.body(11, .semibold))
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var recipeProgressLifecycle: InsightLifecycleStore {
        InsightLifecycleStore(accountID: store.insightLifecycleAccountID)
    }

    @MainActor private func markRecipeInsightSeen(_ candidate: RankedRecipeInsightCandidate) {
        // Opening an action does not remove or suppress the suggestion. Seen remains
        // presentable after returning, refreshing and relaunching with the same evidence.
        _ = recipeProgressLifecycle.markSeen(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint)
    }

    @MainActor private func resolveRecipeInsight(_ candidate: RankedRecipeInsightCandidate) {
        recipeProgressRefreshGeneration += 1
        guard recipeProgressLifecycle.resolve(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint) else { return }
        recipeProgressCandidates.removeAll { $0.id == candidate.id }
        recipeProgressSuppressed = recipeProgressCandidates.isEmpty
    }

    @MainActor private func dismissRecipeInsight(_ candidate: RankedRecipeInsightCandidate) {
        recipeProgressRefreshGeneration += 1
        recipeProgressLifecycle.dismiss(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint)
        recipeProgressCandidates.removeAll { $0.id == candidate.id }
        recipeProgressSuppressed = recipeProgressCandidates.isEmpty
    }

    @MainActor private func snoozeRecipeInsight(_ candidate: RankedRecipeInsightCandidate) {
        recipeProgressRefreshGeneration += 1
        recipeProgressLifecycle.snooze(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint, until: Date().addingTimeInterval(24 * 60 * 60))
        recipeProgressCandidates.removeAll { $0.id == candidate.id }
        recipeProgressSuppressed = recipeProgressCandidates.isEmpty
    }

    private func insightActionTitle(for candidate: RankedRecipeInsightCandidate) -> String {
        switch candidate.action {
        case .recipes: return candidate.id == "recipe-duplicates" ? "Review saved recipes" : "Explore new recipes"
        case .cookingHistory: return "See your cooking history"
        case .shoppingList: return "Review shopping list"
        case .foodDiary: return "Review food diary"
        }
    }

    private func insightActionSymbol(for candidate: RankedRecipeInsightCandidate) -> String {
        switch candidate.action {
        case .recipes: return candidate.id == "recipe-duplicates" ? "doc.text.magnifyingglass" : "books.vertical"
        case .cookingHistory: return "calendar.badge.clock"
        case .shoppingList: return "basket"
        case .foodDiary: return "fork.knife"
        }
    }

    @MainActor private func openInsightDestination(for candidate: RankedRecipeInsightCandidate) {
        // A pushed hub already owns the requested cooking-history destination. Dismissing
        // here would pop to Journal and race the subsequent path assignment.
        if candidate.action == .cookingHistory, !isRoot {
            cookingHistoryScrollRequest += 1
            return
        }
        // Other presentation contexts still dismiss before switching destinations.
        dismiss()
        switch candidate.action {
        case .recipes:
            store.filter.clear()
            store.select(.library)
        case .cookingHistory:
            store.openInsightsHub()
        case .shoppingList:
            store.shoppingPath = []
            store.select(.shopping)
        case .foodDiary:
            store.select(.settings)
            store.showNutritionDiary = true
        }
    }

    @MainActor private func refreshRecipeProgressInsight() async {
        recipeProgressRefreshGeneration += 1
        let generation = recipeProgressRefreshGeneration
        recipeProgressLoading = true
        defer {
            if generation == recipeProgressRefreshGeneration { recipeProgressLoading = false }
        }

        let input = RecipeProgressInsightInput.make(recipes: store.recipes, historyEvents: store.journalCookingHistory.events)
        // A corrupt diary is unavailable, not empty: pass nil so diary-derived insights
        // are skipped instead of computed against a fabricated empty diary.
        let nutritionEntries = store.nutritionEntriesForInsights()
        let lifecycle = recipeProgressLifecycle
        var hadSuppressed = false
        let eligible = RecipeProgressInsightService.candidates(
            for: input,
            shoppingItems: store.shopping,
            nutritionEntries: nutritionEntries
        ) { candidate in
            let presentable = lifecycle.shouldPresent(id: candidate.id, evidenceFingerprint: candidate.evidenceFingerprint)
            if !presentable { hadSuppressed = true }
            return presentable
        }

        guard generation == recipeProgressRefreshGeneration else { return }
        recipeProgressCandidates = eligible
        recipeProgressSuppressed = eligible.isEmpty && hadSuppressed
    }

    @ViewBuilder private var bodyToday: some View {
        card("Your body today") {
            if InsightsSampleMarking.requiresSampleBadge(tileID: "bodyToday", isSample: model.isSample) {
                HStack(spacing: 8) {
                    sampleBadge()
                    Text("Not your personal Health data.").font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
            } else if let err = model.requestError {
                Label("Apple Health request failed: \(err)", systemImage: "exclamationmark.triangle")
                    .font(AteFont.body(13)).foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("insights.healthError")
            }
            let presentation = InsightsHealthPresentation.make(access: model.access)
            switch model.access {
            case .unavailable:
                quietHealthNotice("Apple Health isn't available", symbol: "heart.slash",
                                  detail: "This device has no Health app (e.g. iPad).",
                                  id: "insights.unavailable", presentation: presentation)
            case .entitlementMissing:
                quietHealthNotice("Health access not in this build", symbol: "lock.shield",
                                  detail: "This copy was signed without Apple Health access. Re-sideload the latest Ate build with the same Apple ID.",
                                  id: "insights.entitlementMissing", presentation: presentation)
            case .denied:
                quietHealthNotice("Health access is off", symbol: "hand.raised",
                                  detail: "Turn it on in Settings › Health › Data Access & Devices › ate.",
                                  id: "insights.denied", presentation: presentation)
            case .notDetermined:
                quietHealthConnect(presentation)
            case .requested:
                if model.loading { ProgressView() }
                else if let c = model.context {
                    Label(c.insight.state.title, systemImage: c.insight.state.symbol).font(AteFont.display(20))
                        .accessibilityIdentifier("insights.state")
                    Text(c.insight.headline).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                    StepsSparkline(days: c.summary.days)
                    if let top = c.suggestions.first {
                        Button { openRecipe = RecipeSheetTarget(id: top.recipeID) } label: {
                            insightActionLabel("Next meal idea: \(top.title)", symbol: "fork.knife")
                        }
                        .accessibilityIdentifier("insights.topMealIdea")
                    }
                } else {
                    quietHealthNotice("No recent Health data", symbol: "chart.line.downtrend.xyaxis",
                                      detail: "Wear your Apple Watch or carry your iPhone, then pull to refresh.",
                                      id: "insights.noData", presentation: presentation)
                }
            }
        }
        .font(AteFont.body(14))
    }

    private func sampleBadge(id: String = "insights.sampleBadge") -> some View {
        Label("Sample data", systemImage: "testtube.2").font(AteFont.body(12, .semibold)).foregroundStyle(Theme.primary)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.primary.opacity(0.12), in: Capsule())
            .accessibilityIdentifier(id)
    }

    /// Audit direction: Health is an optional extra. Until it is connected, setup is one compact,
    /// quiet row - never a dominant warning or a full-width primary takeover.
    @ViewBuilder private func quietHealthConnect(_ presentation: InsightsHealthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square")
                    .font(AteFont.body(14, .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                Text("Apple Health (optional)")
                    .font(AteFont.body(13, .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                if presentation.showsConnect {
                    Button("Connect Apple Health") { Task { await model.tapConnect(recipes: store.recipes) } }
                        .buttonStyle(.ate(.secondary, height: 36))
                        .accessibilityIdentifier("insights.connect")
                }
            }
            Text("Connect read-only for meal ideas that fit your sleep, steps and workouts. Your health data stays on this iPhone.")
                .font(AteFont.body(12))
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    /// Quiet replacement for the old full-card unavailable states: one muted notice with only the
    /// actions the presentation contract allows. The beta sample-data path stays available.
    @ViewBuilder
    private func quietHealthNotice(_ title: String, symbol: String, detail: String, id: String, presentation: InsightsHealthPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(AteFont.body(13, .semibold))
                .foregroundStyle(Theme.mutedForeground)
            Text(detail)
                .font(AteFont.body(12))
                .foregroundStyle(Theme.mutedForeground)
            HStack(spacing: 16) {
                if presentation.showsSettings, let u = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { UIApplication.shared.open(u) }
                        .font(AteFont.body(12, .semibold))
                        .accessibilityIdentifier("insights.openSettings")
                }
                if presentation.showsRetry {
                    Button("Try again") { Task { await model.refresh(recipes: store.recipes) } }
                        .font(AteFont.body(12, .semibold))
                        .accessibilityIdentifier("insights.retry")
                }
                if !AppConfig.channel.isEmpty || AppConfig.isUITesting {
                    Button("Use sample data") { Task { await model.useSampleData(recipes: store.recipes) } }
                        .font(AteFont.body(12, .semibold))
                        .accessibilityIdentifier("insights.sampleData")
                }
            }
            .foregroundStyle(Theme.mutedForeground)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
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
                Button("Use sample data") { Task { await model.useSampleData(recipes: store.recipes) } }
                    .accessibilityIdentifier("insights.sampleData")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: insightTileSymbol(for: title))
                    .font(AteFont.body(16, .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title).font(AteFont.display(18))
            }
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 20)
    }

    private func insightTileSymbol(for title: String) -> String {
        switch title {
        case "Cooking tracker": return "calendar"
        case "Recipe & cooking insights": return "chart.line.uptrend.xyaxis"
        case "Your body today": return "heart.text.square"
        case "Suggested meals": return "fork.knife"
        case "Reflect on your day": return "quote.bubble"
        case "Journal moments": return "book.pages"
        default: return "lightbulb"
        }
    }

    private func recipeProgressInsightSymbol(for insight: RecipeProgressInsight) -> String {
        switch insight.title {
        case "Possible overlapping recipe entries": return "doc.on.doc"
        case "This week's cooking": return "calendar"
        case "New recipes in your rotation": return "sparkles"
        case "A cooking streak is taking shape": return "flame"
        case "Your shopping list brings recipes together": return "basket"
        case "Add verified details to your food diary": return "fork.knife"
        case "Your cooking rhythm", "You're building a steady rhythm": return "chart.bar.xaxis"
        case "Your recipe collection is taking shape": return "books.vertical"
        default: return "lightbulb"
        }
    }

    @MainActor private func refreshAllInsights() async {
        async let healthRefresh: Void = model.refresh(recipes: store.recipes)
        await refreshRecipeProgressInsight()
        await healthRefresh
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
                            HStack(spacing: 6) {
                                Text("Today · " + c.insight.state.title).font(AteFont.body(15, .semibold))
                                if InsightsSampleMarking.requiresSampleBadge(tileID: InsightsSampleMarking.libraryTodayCardID, isSample: model.isSample) {
                                    Text("Sample").font(AteFont.body(10, .semibold)).foregroundStyle(Theme.primary)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.primary.opacity(0.12), in: Capsule())
                                        .accessibilityIdentifier("library.todayCard.sampleBadge")
                                }
                            }
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

struct RecipeSheetTarget: Identifiable, Hashable {
    let id: String
    var recordsHealthSuggestionEvidence = true
}

/// Recipe opened from Insights: its own stack + Done, so Back never strands you. Cook mode dismisses the sheet
/// first so the root full-screen cover can present.
struct RecipeSheet: View {
    let recipeID: String
    /// Only recipes opened from a Health suggestion count as the A-HEALTH-08 beta evidence;
    /// other hosts (e.g. the cooking tracker) pass false so it is never recorded for them.
    var recordsHealthSuggestionEvidence = true
    /// Called when the sheet closes to take the user somewhere else (Cook mode or a pushed
    /// route) rather than because they dismissed it, so a host can skip restoring its own context.
    var onLeaveForElsewhere: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RecipeDetailView(recipeID: recipeID)
                // Identity on the real detail container (children stay individually reachable) so
                // journeys can assert exactly WHICH recipe the sheet shows.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recipeSheet.recipe.\(recipeID)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("recipeSheet.done")
                    }
                }
        }
        .onDisappear {
            if recordsHealthSuggestionEvidence { BetaQA.shared.pass("A-HEALTH-08", note: "Opened and closed a suggested recipe") }
        }
        .onChange(of: store.cookTarget) { _, t in
            // Root presents cook mode full-screen; hand off after the sheet is gone.
            guard let t else { return }
            store.cookTarget = nil
            onLeaveForElsewhere?()
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { store.cookTarget = t }
        }
        .onChange(of: store.path) { _, p in if !p.isEmpty { onLeaveForElsewhere?(); dismiss() } }
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
