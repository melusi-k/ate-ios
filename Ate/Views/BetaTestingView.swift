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
    @State private var ci: [String: CIResult] = [:]
    @State private var ciError: String?
    @State private var ciRefreshed: Date?
    @State private var ciLoading = false
    @State private var healthScenario = UserDefaults.standard.string(forKey: HealthServiceFactory.debugKey) ?? ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build \(AppConfig.buildLabel)").font(AteFont.body(13, .semibold)).accessibilityIdentifier("betaBuildLabel")
                    let p = qa.progress()
                    Text("This build: \(p.passed)/\(p.total) \(BetaChecklist.isTierC ? "uncommitted" : "Pilot") device checks passed").font(AteFont.display(20)).accessibilityIdentifier("betaProgress")
                    ProgressView(value: Double(p.passed), total: Double(max(1, p.total))).tint(Theme.primary)
                    Text("These are acceptance checks, not the number of tests run. Auto checks record journeys on this iPhone; other checks need your verdict. Earlier-build evidence is kept separately below.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                }
                Text("Bundled catalogue " + String(BetaChecklist.catalogueRevision.prefix(12)) + " · " + AppConfig.gitSHA)
                    .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                Text("Pilot items are release-readiness requirements, including capabilities still awaiting verification. The total is generated from this build's requirement snapshot, not from the number of executed tests.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                NavigationLink("Catalogue for this build") { BetaCatalogueView() }
                NavigationLink { BetaExpectationsView() } label: { Label(Transparency.betaTitle, systemImage: "info.circle") }
                    .accessibilityIdentifier("betaExpectationsLink")
                let ciPass = ci.values.filter { $0.status == .pass }.count
                Text(ciSummary(passed: ciPass))
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("betaCISummary")
                Text("No published evidence does not mean tests passed, failed, or were skipped. See the build run for execution details.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                if let error = ciError { Text("CI refresh failed: " + error).font(AteFont.body(12)).foregroundStyle(Theme.destructive).accessibilityIdentifier("betaCIError") }
                if let at = ciRefreshed { Text("CI refreshed " + at.formatted(date: .abbreviated, time: .shortened)).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground) }

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
                .onChange(of: healthScenario) { _, v in Task { await store.insightsModel.useScenario(v, recipes: store.recipes) } }
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
                Button { WidgetBridge.publishNow(store, force: true); store.show("Widget refresh requested") } label: {
                    Label("Refresh widgets now", systemImage: "arrow.clockwise")
                }.accessibilityIdentifier("beta.refreshWidgets")
                Text("Checks A-WIDGET, A-LOCK, A-CONTROL and A-INTENT. If the App Group shows missing, widgets can only show “Open ate”; Siri phrases and Control Center still work.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            }
            let passedIDs = Set(BetaChecklist.items.filter { BetaVisibility.isPassed(device: qa.currentResult($0.id), ci: ci[$0.id], build: AppConfig.buildLabel) }.map(\.id))
            ForEach(BetaChecklist.categories, id: \.self) { c in
                let open = BetaChecklist.items.filter { $0.category == c && !passedIDs.contains($0.id) }
                if !open.isEmpty {
                    let p = qa.progress(c)
                    Section("\(c) — \(p.passed)/\(p.total)") {
                        ForEach(open) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.currentResult(item.id), ci: ci[item.id]) }
                        }
                    }
                }
            }
            if !passedIDs.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showPassed) {
                        ForEach(BetaChecklist.items.filter { passedIDs.contains($0.id) }) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.currentResult(item.id), ci: ci[item.id]) }
                        }
                    } label: { Text("Passed (\(passedIDs.count))").font(AteFont.body(15, .semibold)) }
                    .accessibilityIdentifier("beta.passedGroup")
                }
            }
            if BetaChecklist.isTierC {
                Section {
                    DisclosureGroup(isExpanded: $showTierA) {
                        ForEach(BetaChecklist.tierA) { item in
                            NavigationLink { BetaItemView(item: item) } label: { BetaRow(item: item, result: qa.currentResult(item.id), ci: ci[item.id]) }
                        }
                    } label: {
                        let done = BetaChecklist.tierA.filter { qa.currentResult($0.id).status == .pass }.count
                        Text("Pilot gate results (\(done)/\(BetaChecklist.tierA.count) passed)").font(AteFont.body(15, .semibold))
                    }
                    .accessibilityIdentifier("beta.tierAGroup")
                }
            }
            let historical = BetaChecklist.all.filter { !qa.previousResults($0.id).isEmpty }
            if !historical.isEmpty {
                Section("Earlier-build evidence") {
                    Text("Preserved for reference, not counted as verification of this build. Legacy records may have no commit/run identity. Only records still stored on this iPhone can be recovered.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    ForEach(historical) { item in
                        NavigationLink { BetaItemView(item: item) } label: {
                            Text(item.id + " · " + item.title).font(AteFont.body(13))
                        }
                    }
                }
            }
            Section("Results") {
                if let warning = qa.persistenceWarning { Text(warning).foregroundStyle(Theme.destructive) }
                if !qa.hasVerifiableBuildIdentity {
                    Text("This local/development build has no verifiable release identity. Verdicts can be recorded, but are not counted as current-build verification or eligible for upload.")
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("betaUnverifiedBuildNotice")
                }
                Button("Export results (JSON + Markdown)") {
                    let j = writeTemp("ate-beta-\(AppConfig.buildNumber).json", qa.exportJSON())
                    let m = writeTemp("ate-beta-\(AppConfig.buildNumber).md", Data(qa.exportMarkdown().utf8))
                    share = ShareItems(items: [j, m].compactMap { $0 })
                }
                Text("\(qa.legacyNotUploadedCount) legacy/unknown records excluded from upload and preserved in the local export. Only records with captured build, catalogue and source/run identity are eligible; this does not repair existing cloud history.")
                    .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                if let s = store.session {
                    Button("Upload results to ate cloud") { Task { uploadMessage = await qa.upload(session: s) ?? "Uploaded ✅" } }
                }
                if let m = uploadMessage { Text(m).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground) }
                Button("Reset this build's results", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Beta testing")
        .onAppear { qa.detectTierC() }
        .task(id: store.session?.userID) { await refreshCI() }
        .refreshable { await refreshCI() }
        .confirmationDialog("Reset only this build's results? Earlier-build history is kept.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset this build", role: .destructive) { qa.resetCurrentBuild() }
        }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
    }

    private func ciSummary(passed: Int) -> String {
        switch BetaCIViewState.resolve(loading: ciLoading, error: ciError, refreshed: ciRefreshed, count: ci.count) {
        case .loading: return "CI: loading this build's evidence"
        case .unknown: return "CI: status unknown"
        case .notLoaded: return "CI: not loaded"
        case .noEvidence: return "CI: no published evidence for this exact build"
        case .evidence: return "CI for this build: \(passed)/\(ci.count) published checks passing"
        }
    }
    @MainActor private func refreshCI() async {
        ci = [:]; ciError = nil; ciRefreshed = nil; ciLoading = true
        defer { ciLoading = false }
        if AppConfig.isUITesting {
            // Deterministic presentation fixtures only. They never write release identity,
            // hit the live backend or qualify a real refresh/upgrade.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-qaBetaCINotLoaded") { return }
            if args.contains("-qaBetaCIRefreshFailure") {
                ciError = "Simulated refresh failure (UI test fixture)"; return
            }
            ci = CIStatus.results; ciRefreshed = Date(); return
        }
        guard let session = store.session else { ciError = "Sign in to fetch this build's evidence."; return }
        let userID = session.userID
        await CIStatus.refresh(session: session)
        guard store.session?.userID == userID else { return }
        ci = CIStatus.results; ciError = CIStatus.lastError; ciRefreshed = CIStatus.lastRefreshed
    }

}

struct BetaCatalogueView: View {
    var body: some View {
        List {
            Section {
                Text(AppConfig.buildLabel)
                Text("Source commit: " + AppConfig.gitSHAFull).textSelection(.enabled)
                Text("Catalogue: " + BetaChecklist.catalogueRevision).textSelection(.enabled)
                Text("This is the documented acceptance inventory bundled with this source build. Inclusion is not a claim of implementation or a pass. Historical catalogue snapshots are retained from this repair onward; old catalogues are not reconstructed from today's wording.")
            }
            Section("Pilot requirements (\(BetaChecklist.tierA.count))") {
                ForEach(BetaChecklist.tierA) { item in
                    NavigationLink { BetaItemView(item: item) } label: { Text(item.id + " · " + item.title) }
                }
            }
            Section("Other documented requirements (\(BetaChecklist.tierC.count))") {
                Text("No committed release gate. Not added to the Pilot denominator, and not necessarily implemented in this build.")
                ForEach(BetaChecklist.tierC) { item in
                    NavigationLink { BetaItemView(item: item) } label: { Text(item.id + " · " + item.title) }
                }
            }
        }.navigationTitle("Build catalogue")
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
            let r = qa.currentResult(item.id)
            Section("Status") {
                Text("\(r.status.symbol) \(r.status.rawValue)\(r.auto ? " (auto)" : "")" + (r.status == .untested ? "" : " · \(r.ts.formatted(date: .abbreviated, time: .shortened)) · \(r.build)"))
                if !r.note.isEmpty { Text(r.note).font(AteFont.body(12)).textSelection(.enabled) }
            }
            if !qa.previousResults(item.id).isEmpty {
                Section("Earlier-build evidence") {
                    ForEach(Array(qa.previousResults(item.id).enumerated()), id: \.offset) { _, old in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(old.status.symbol + " " + old.status.rawValue + " · " + old.build)
                            Text(old.ts.formatted(date: .abbreviated, time: .shortened))
                            Text("Commit: " + (old.commitSHA ?? "Unknown (legacy)") + " · Run: " + (old.runID ?? "Unknown (legacy)"))
                            if !old.note.isEmpty { Text(old.note) }
                        }.font(AteFont.body(12))
                    }
                }
            }
            Section("Your verdict for this build") {
                TextField("Note (what happened)", text: $note, axis: .vertical)
                HStack {
                    Button("Pass") { qa.set(item.id, .pass, note: note, auto: false) }.tint(.green)
                    Button("Fail") { qa.set(item.id, .fail, note: note, auto: false) }.tint(Theme.destructive)
                    Button("Skip") { qa.set(item.id, .skip, note: note, auto: false) }.tint(.gray)
                }.buttonStyle(.bordered)
            }
        }
        .navigationTitle(item.id)
        .onAppear { note = qa.currentResult(item.id).note }
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
