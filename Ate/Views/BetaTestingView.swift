import SwiftUI

/// Settings › Beta testing: every item for this build's tier (Tier A, or Tier C on TierC builds) with live ✅/❌ status, manual verdicts, export, upload and reset.
struct BetaTestingView: View {
    @Environment(AppStore.self) private var store
    @State private var qa = BetaQA.shared
    @State private var share: ShareItems?
    @State private var confirmReset = false
    @State private var showPassed = false
    @State private var showTierA = false
    @State private var uploadMessage: String?
    @State private var ci = CIStatus.results
    @State private var healthScenario = UserDefaults.standard.string(forKey: HealthServiceFactory.debugKey) ?? ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build \(AppConfig.buildLabel)").font(AteFont.body(13, .semibold)).accessibilityIdentifier("betaBuildLabel")
                    let p = qa.progress()
                    Text("\(BetaChecklist.tierName): \(p.passed)/\(p.total) passed").font(AteFont.display(20)).accessibilityIdentifier("betaProgress")
                    ProgressView(value: Double(p.passed), total: Double(max(1, p.total))).tint(Theme.primary)
                    Text("Items marked ‘auto’ tick themselves when the journey really completes on this iPhone, and turn ❌ with the error if it fails. Others need your verdict.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
                NavigationLink { BetaExpectationsView() } label: { Label(Transparency.betaTitle, systemImage: "info.circle") }
                    .accessibilityIdentifier("betaExpectationsLink")
                let ciPass = ci.values.filter { $0.status == .pass }.count
                Text(ci.isEmpty ? "CI: no simulator/backend results yet" + (store.session == nil ? " (sign in to see them)" : "")
                                : "CI: \(ciPass)/\(ci.count) automated checks passing")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("betaCISummary")
            }
            Section("Health insights") {
                Picker("Health data", selection: $healthScenario) {
                    Text("Real Apple Health").tag("")
                    ForEach(HealthServiceFactory.scenarios, id: \.self) { Text("Mock: " + $0).tag($0) }
                }
                .accessibilityIdentifier("beta.healthScenario")
                Button { UIPasteboard.general.string = HealthDiagnostics.line; store.show("Health diagnostics copied") } label: {
                    Text(HealthDiagnostics.line).font(AteFont.body(13)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("beta.healthDiagnostics")
                .onChange(of: healthScenario) { _, v in Task { await InsightsModel.shared.useScenario(v, recipes: store.recipes) } }
                NavigationLink { InsightsView() } label: { Label("Open Insights & journal", systemImage: "heart.text.square") }
                    .accessibilityIdentifier("beta.openInsights")
                Text("Checks H-01…H-08: connect, state title, 3 meal ideas, prompts, save to journal, denied/unavailable/no-entitlement copy. Mock data never touches Apple Health.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            }
            Section("Widgets, controls & Siri") {
                Button { UIPasteboard.general.string = WidgetBridge.diagnostics; store.show("Widget diagnostics copied") } label: {
                    Text(WidgetBridge.diagnostics).font(AteFont.body(13)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("beta.widgetDiagnostics")
                Button { UIPasteboard.general.string = AteShortcuts.diagnostics; store.show("Siri diagnostics copied") } label: {
                    Text(AteShortcuts.diagnostics).font(AteFont.body(12)).foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("beta.siriDiagnostics")
                Button { WidgetBridge.publishNow(store); WidgetKinds.reloadAll(); store.show("Widgets refreshed") } label: {
                    Label("Refresh widgets now", systemImage: "arrow.clockwise")
                }.accessibilityIdentifier("beta.refreshWidgets")
                Text("Checks A-WIDGET, A-LOCK, A-CONTROL and A-INTENT. If the App Group shows missing, widgets can only show “Open ate”; Siri phrases and Control Center still work.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            }
            let passedIDs = Set(BetaChecklist.items.filter { BetaVisibility.isPassed(device: qa.result($0.id), ci: ci[$0.id], build: AppConfig.buildNumber) }.map(\.id))
            ForEach(BetaChecklist.categories, id: \.self) { c in
                let open = BetaChecklist.items.filter { $0.category == c && !passedIDs.contains($0.id) }
                if !open.isEmpty {
                    let p = qa.progress(c)
                    Section("\(c) — \(p.passed)/\(p.total)") {
                        ForEach(open) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.result(item.id), ci: ci[item.id]) }
                        }
                    }
                }
            }
            if !passedIDs.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showPassed) {
                        ForEach(BetaChecklist.items.filter { passedIDs.contains($0.id) }) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.result(item.id), ci: ci[item.id]) }
                        }
                    } label: { Text("Passed (\(passedIDs.count))").font(AteFont.body(15, .semibold)) }
                    .accessibilityIdentifier("beta.passedGroup")
                }
            }
            if BetaChecklist.isTierC {
                Section {
                    DisclosureGroup(isExpanded: $showTierA) {
                        ForEach(BetaChecklist.tierA) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.result(item.id), ci: ci[item.id]) }
                        }
                    } label: {
                        let done = BetaChecklist.tierA.filter { qa.result($0.id).status == .pass }.count
                        Text("Tier A results (\(done)/\(BetaChecklist.tierA.count) passed)").font(AteFont.body(15, .semibold))
                    }
                    .accessibilityIdentifier("beta.tierAGroup")
                }
            }
            Section("Results") {
                Button("Export results (JSON + Markdown)") {
                    let j = writeTemp("ate-beta-\(AppConfig.buildNumber).json", qa.exportJSON())
                    let m = writeTemp("ate-beta-\(AppConfig.buildNumber).md", Data(qa.exportMarkdown().utf8))
                    share = ShareItems(items: [j, m].compactMap { $0 })
                }
                if let s = store.session {
                    Button("Upload results to ate cloud") { Task { uploadMessage = await qa.upload(session: s) ?? "Uploaded ✅" } }
                }
                if let m = uploadMessage { Text(m).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground) }
                Button("Reset all results", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Beta testing")
        .onAppear { qa.detectTierC() }
        .task { if let s = store.session { await CIStatus.refresh(session: s); ci = CIStatus.results } }
        .refreshable { if let s = store.session { await CIStatus.refresh(session: s); ci = CIStatus.results } }
        .confirmationDialog("Reset every beta result on this iPhone?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { qa.reset() }
        }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
    }

}

struct BetaRow: View {
    let item: BetaItem
    let result: BetaQA.Result
    var ci: CIResult? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Text(result.status.symbol)
                Text("📱").font(.caption2)
            }.frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(AteFont.body(14, .semibold))
                Text(item.id + (item.auto ? " · auto" : " · manual")).font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                if !result.note.isEmpty { Text(result.note).font(AteFont.body(11)).foregroundStyle(result.status == .fail ? Theme.destructive : Theme.mutedForeground).lineLimit(2) }
            }
            Spacer(minLength: 4)
            if let ci {
                VStack(spacing: 2) {
                    Text(ci.status.symbol)
                    Text("CI").font(.caption2.weight(.semibold))
                }.frame(width: 28).accessibilityLabel("CI \(ci.status.rawValue)")
            }
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("beta.\(item.id)")
    }
}

struct BetaItemView: View {
    let item: BetaItem
    @State private var qa = BetaQA.shared
    @State private var note = ""
    var body: some View {
        Form {
            Section("\(item.id) · \(item.category)") {
                Text(item.title).font(AteFont.display(18))
                Text(item.how).font(AteFont.body(13))
            }
            let r = qa.result(item.id)
            Section("Status") {
                Text("\(r.status.symbol) \(r.status.rawValue)\(r.auto ? " (auto)" : "")" + (r.status == .untested ? "" : " · \(r.ts.formatted(date: .abbreviated, time: .shortened)) · \(r.build)"))
                if !r.note.isEmpty { Text(r.note).font(AteFont.body(12)).textSelection(.enabled) }
            }
            Section("Your verdict") {
                TextField("Note (what happened)", text: $note, axis: .vertical)
                HStack {
                    Button("Pass") { qa.set(item.id, .pass, note: note, auto: false) }.tint(.green)
                    Button("Fail") { qa.set(item.id, .fail, note: note, auto: false) }.tint(Theme.destructive)
                    Button("Skip") { qa.set(item.id, .skip, note: note, auto: false) }.tint(.gray)
                }.buttonStyle(.bordered)
            }
        }
        .navigationTitle(item.id)
        .onAppear { note = qa.result(item.id).note }
    }
}

/// Proper page for "What to expect in this beta" (was a collapsed, unlocalized disclosure in About).
struct BetaExpectationsView: View {
    var body: some View {
        List {
            Section { Text("Build \(AppConfig.buildLabel)").font(AteFont.body(13, .semibold)) }
            ForEach(Transparency.beta, id: \.self) { line in
                Label { Text(line).font(AteFont.body(14)) } icon: { Image(systemName: "info.circle").foregroundStyle(Theme.primary) }
            }
        }
        .navigationTitle(Transparency.betaTitle)
        .onAppear { BetaQA.shared.pass("A-LAUNCH-01", note: "Opened “What to expect in this beta”") }
        .accessibilityIdentifier("betaExpectations")
    }
}

/// First-launch banner on a channel build (e.g. TierA).
struct BetaBanner: View {
    @State private var qa = BetaQA.shared
    var open: () -> Void
    var body: some View {
        if !AppConfig.channel.isEmpty, !qa.bannerDismissed, !AppConfig.isUITesting {
            HStack(spacing: 10) {
                Image(systemName: "checklist").foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(AppConfig.channel) beta build").font(AteFont.body(14, .semibold))
                    Text("See what to test — \(qa.progress().passed)/\(qa.progress().total) done").font(AteFont.body(12))
                }
                Spacer()
                Button("Open") { qa.bannerDismissed = true; open() }.buttonStyle(.borderedProminent).tint(Theme.primary)
                Button { qa.bannerDismissed = true } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss beta banner")
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }
}
