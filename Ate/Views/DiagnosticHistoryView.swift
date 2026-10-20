import SwiftUI

struct DiagnosticHistoryView: View {
    @State private var entries = DiagnosticHistory.shared.entries
    @State private var share: ShareItems?
    @State private var confirmClear = false
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("Recent app events are kept on this iPhone only. Ate records a limited set of event categories, not recipe content, prompts, account details or raw error messages.")
                    .font(AteFont.body(13))
                    .foregroundStyle(Theme.mutedForeground)
                Text("This history can help explain recorded failures, but it cannot guarantee an exact record of a crash or force-quit.")
                    .font(AteFont.body(13))
                    .foregroundStyle(Theme.mutedForeground)
            }
            Section("Recent events · \(entries.count)") {
                if entries.isEmpty {
                    ContentUnavailableView("No diagnostic events yet", systemImage: "waveform.path", description: Text("App and recovery events will appear here as they occur."))
                } else {
                    ForEach(entries.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(AteFont.body(14, .medium))
                            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(AteFont.body(12))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section("Diagnostic report") {
                Button {
                    let report = DiagnosticHistory.shared.exportReport(
                        appVersion: AppConfig.appVersion,
                        buildNumber: AppConfig.buildNumber
                    )
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ate-diagnostics-\(AppConfig.buildNumber).txt")
                    do {
                        try Data(report.utf8).write(to: url, options: .atomic)
                        share = ShareItems(items: [url])
                    } catch {
                        store.show("Couldn't create the diagnostic report.", error: true)
                    }
                } label: {
                    Label("Export diagnostic report", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("diagnostics.export")
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Clear diagnostic history", systemImage: "trash")
                }
                .accessibilityIdentifier("diagnostics.clear")
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear { entries = DiagnosticHistory.shared.entries }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
        .confirmationDialog("Clear diagnostic history on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                DiagnosticHistory.shared.clear()
                entries = []
                store.show("Diagnostic history cleared")
            }
        }
    }
}
