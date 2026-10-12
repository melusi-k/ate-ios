import SwiftUI

/// Beta hub: launch-readiness checks and expectations for pilot testers.
struct MoreView: View {
    @Environment(AppStore.self) private var store
    @State private var qa = BetaQA.shared

    var body: some View {
        Group {
            if AppConfig.isBetaBuild {
            List {
                Section {
                    // More's path is also changed by the beta banner/deep-link handler. A direct
                    // destination avoids iOS resolving a typed path destination while that path changes.
                    NavigationLink {
                        BetaTestingView()
                    } label: {
                        LabeledContent { Text("\(qa.progress().passed)/\(qa.progress().total)").monospacedDigit() } label: {
                            Label("Beta testing", systemImage: "checklist")
                        }
                    }
                    .accessibilityIdentifier("more.betaTesting")
                    NavigationLink {
                        BetaExpectationsView()
                    } label: {
                        Label(Transparency.betaTitle, systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("betaNote")
                } header: {
                    Text("Beta testing")
                } footer: {
                    Text("Run the pilot checks, record results, and see what to expect from this build.")
                }
            }
            } else {
                SettingsView()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Beta")
        .navigationBarTitleDisplayMode(.large)
        .softTopEdge()
        // Deep requests from the beta banner still land on the Beta screen.
        .onChange(of: qa.openRequested, initial: true) { _, v in
            if v {
                qa.openRequested = false
                guard AppConfig.isBetaBuild else { return }
                store.morePath = [.beta]
            }
        }
    }
}

/// Diagnostics shown in Settings › About for builds with Live Activities enabled.
struct LiveActivityDiagnosticsView: View {
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live Activity").font(AteFont.body(12, .semibold))
            Text("areActivitiesEnabled: \(LiveActivityDiagnostics.enabledNow ? "yes" : "NO")")
            Text("Last request: " + LiveActivityDiagnostics.lastResult)
            ForEach(Array(LiveActivityLog.shared.entries.dropFirst().prefix(8).enumerated()), id: \.offset) {
                Text("· " + $0.element).font(AteFont.body(11))
            }
            Text("Active activities: \(LiveActivityDiagnostics.activeCount)")
            Text("Widget extension: " + (LiveActivityDiagnostics.widgetAppexPresent
                 ? "present (\(LiveActivityDiagnostics.widgetBundleID ?? "?"))"
                 : "MISSING — re-sideload with extensions kept"))
            Text("App bundle ID: \(Bundle.main.bundleIdentifier ?? "?")")
            Text("PlugIns: " + (LiveActivityDiagnostics.plugIns.isEmpty ? "none" : LiveActivityDiagnostics.plugIns.joined(separator: ", ")))
            Button("Refresh") { tick += 1 }
                .font(AteFont.body(12, .semibold))
                .tint(Theme.primary)
        }
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
        .font(AteFont.body(12))
        .foregroundStyle(Theme.mutedForeground)
        .textSelection(.enabled)
        .accessibilityIdentifier("liveActivityDiagnostics")
    }
}
