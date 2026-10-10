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
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("More").font(AteFont.display(30))

                    section("Beta testing") {
                        NavigationLink { BetaTestingView() } label: {
                            HStack {
                                Image(systemName: "checklist").foregroundStyle(Theme.primary)
                                Text("Beta testing").font(AteFont.body(15, .semibold))
                                Spacer()
                                Text("\(qa.progress().passed)/\(qa.progress().total)").font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("more.betaTesting")
                        NavigationLink { BetaExpectationsView() } label: {
                            HStack {
                                Image(systemName: "info.circle").foregroundStyle(Theme.primary)
                                Text(Transparency.betaTitle).font(AteFont.body(15, .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("betaNote")
                    }
                    section("Health") {
                        NavigationLink { InsightsView() } label: {
                            HStack {
                                Image(systemName: "heart.text.square").foregroundStyle(Theme.primary)
                                Text("Insights & journal").font(AteFont.body(15, .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedForeground)
                            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("more.insights")
                    }
                    section("Collections") {
                        ForEach([RecipeCollection.quick, .favourites, .recentlyAdded, .recentlyCooked], id: \.self) { c in
                            collectionRow(c)
                        }
                    }
                    let tags = IngredientTags.collections(in: store.recipes)
                    if !tags.isEmpty {
                        section("By ingredient") {
                            ForEach(tags, id: \.self) { collectionRow(.ingredient($0)) }
                        }
                    }
                    section("Tools") {
                        row("Export recipes", "arrow.down.doc", id: "more.export") {
                            if let u = writeTemp("ate-recipes.json", store.exportJSON()) { share = ShareItems(items: [u]) }
                        }
                        row("Import recipes", "square.and.arrow.down", id: "more.import") { importing = true }
                        row("Replay intro", "sparkles", id: "replayOnboarding") { store.replayOnboarding() }
                        if let u = AppConfig.privacyURL { linkRow("Privacy Policy", "hand.raised", u, id: "settingsPrivacy") }
                        if let u = AppConfig.termsURL { linkRow("Terms of Use", "doc.text", u, id: "settingsTerms") }
                    }
                    section("About") {
                        Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))" + (AppConfig.channel.isEmpty ? "" : " · \(AppConfig.channel)"))
                            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("aboutVersion")
                        Text(Transparency.ai).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                            .accessibilityIdentifier("aiTransparency")
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
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .pageWidth()
            }
        }
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
        .navigationDestination(isPresented: $qa.openRequested) { BetaTestingView() }
        .navigationDestination(isPresented: $nav.open) { InsightsView() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AteFont.display(18))
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 20)
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
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.primary).frame(width: 24)
                Text(title).font(AteFont.body(16, .medium))
                Spacer()
                if let trailing { Text(trailing).font(AteFont.body(14)).monospacedDigit().foregroundStyle(Theme.mutedForeground) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: URL, id: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.primary).frame(width: 24)
                Text(title).font(AteFont.body(16, .medium)).foregroundStyle(Theme.foreground)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
            }.frame(minHeight: 44)
        }.accessibilityIdentifier(id)
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
