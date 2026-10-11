import SwiftUI
import UniformTypeIdentifiers

/// "More" tab: collections, ingredient shortcuts, tools and About — in ate's own card styling.
struct MoreView: View {
    @Environment(AppStore.self) private var store
    @State private var importing = false
    @State private var share: ShareItems?
    @State private var qa = BetaQA.shared
    @State private var nav = InsightsNavState.shared

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.beta) {
                    LabeledContent { Text("\(qa.progress().passed)/\(qa.progress().total)").monospacedDigit() } label: {
                        Label("Beta testing", systemImage: "checklist")
                    }
                }.accessibilityIdentifier("more.betaTesting")
                NavigationLink(value: Route.betaNote) { Label(Transparency.betaTitle, systemImage: "info.circle") }
                    .accessibilityIdentifier("betaNote")
            } header: { Text("Beta testing") }
            Section {
                NavigationLink(value: Route.insights) { Label("Insights & journal", systemImage: "heart.text.square") }
                    .accessibilityIdentifier("more.insights")
                NavigationLink(value: Route.journal) { Label("Journal", systemImage: "book.closed") }
                    .accessibilityIdentifier("more.journal")
            } header: { Text("Health") } footer: { Text("Read-only Apple Health signals turned into meal ideas and journal prompts.") }
            Section("Collections") {
                ForEach([RecipeCollection.quick, .favourites, .recentlyAdded, .recentlyCooked], id: \.self) { collectionRow($0) }
            }
            let tags = IngredientTags.collections(in: store.recipes)
            if !tags.isEmpty {
                Section("By ingredient") { ForEach(tags, id: \.self) { collectionRow(.ingredient($0)) } }
            }
            Section("Tools") {
                row("Export recipes", "arrow.down.doc", id: "more.export") {
                    if let u = writeTemp("ate-recipes.json", store.exportJSON()) { share = ShareItems(items: [u]) }
                }
                row("Import recipes", "square.and.arrow.down", id: "more.import") { importing = true }
                row("Replay intro", "sparkles", id: "replayOnboarding") { store.replayOnboarding() }
                if let u = AppConfig.privacyURL { Link(destination: u) { Label("Privacy Policy", systemImage: "hand.raised") }.accessibilityIdentifier("settingsPrivacy") }
                if let u = AppConfig.termsURL { Link(destination: u) { Label("Terms of Use", systemImage: "doc.text") }.accessibilityIdentifier("settingsTerms") }
            }
            Section {
                Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))" + (AppConfig.channel.isEmpty ? "" : " · \(AppConfig.channel)"))
                    .accessibilityIdentifier("aboutVersion")
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI diagnostics").font(AteFont.body(12, .semibold))
                    Text("Model: " + OnDeviceBackend.availabilityDescription)
                    Text("Last generation: " + (GenerationLog.last?.summary ?? "none yet"))
                        .accessibilityIdentifier("lastGeneration")
                }
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine).accessibilityIdentifier("aiDiagnostics")
                LiveActivityDiagnosticsView()
            } header: { Text("About") } footer: {
                Text(Transparency.ai).accessibilityIdentifier("aiTransparency")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let n = try store.importJSON(try Data(contentsOf: url))
                store.show(n > 0 ? "Imported \(n) recipe\(n == 1 ? "" : "s")" : "Library up to date")
            } catch { store.show("That file isn't a ate export.", error: true) }
        }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
        // Deep requests (beta banner, Today card) push values onto the More path, so path state never desyncs.
        .onChange(of: qa.openRequested, initial: true) { _, v in if v { qa.openRequested = false; store.morePath = [.beta] } }
        .onChange(of: nav.open, initial: true) { _, v in if v { nav.open = false; store.morePath = [.insights] } }
    }

    private func collectionRow(_ c: RecipeCollection) -> some View {
        var f = RecipeFilter(); f.collection = c
        let n = f.apply(store.recipes).count
        return row(c.title, c.symbol, trailing: "\(n)", id: "more." + c.title) {
            store.filter.clear()
            store.filter.collection = c
            store.path = []
            store.tab = .library
        }
    }

    private func row(_ title: String, _ symbol: String, trailing: String? = nil, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent { if let trailing { Text(trailing).monospacedDigit() } } label: { Label(title, systemImage: symbol) }
                .contentShape(Rectangle())
        }
        .foregroundStyle(Theme.foreground)
        .accessibilityIdentifier(id)
    }
}

/// More → About → Live Activity: why the Dynamic Island might be silent on a sideloaded build.
struct LiveActivityDiagnosticsView: View {
    @State private var tick = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live Activity").font(AteFont.body(12, .semibold))
            Text("areActivitiesEnabled: \(LiveActivityDiagnostics.enabledNow ? "yes" : "NO")")
            Text("Last request: " + LiveActivityDiagnostics.lastResult)
            ForEach(Array(LiveActivityLog.shared.entries.dropFirst().prefix(8).enumerated()), id: \.offset) { Text("· " + $0.element).font(AteFont.body(11)) }
            Text("Active activities: \(LiveActivityDiagnostics.activeCount)")
            Text("Widget extension: " + (LiveActivityDiagnostics.widgetAppexPresent
                 ? "present (\(LiveActivityDiagnostics.widgetBundleID ?? "?"))" : "MISSING — re-sideload with extensions kept"))
            Text("App bundle ID: \(Bundle.main.bundleIdentifier ?? "?")")
            Text("PlugIns: " + (LiveActivityDiagnostics.plugIns.isEmpty ? "none" : LiveActivityDiagnostics.plugIns.joined(separator: ", ")))
            Button("Refresh") { tick += 1 }.font(AteFont.body(12, .semibold)).tint(Theme.primary)
        }
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
        .textSelection(.enabled)
        .accessibilityIdentifier("liveActivityDiagnostics")
    }
}
