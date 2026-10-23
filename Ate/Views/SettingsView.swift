import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(JournalingSuggestionsGate.settingKey) private var journalingEnabled = false
    @Environment(AppStore.self) private var store
    @State private var importing = false
    @State private var confirmClear = false
    @State private var activeSheet: SettingsSheet?

    private enum SettingsSheet: Identifiable {
        case share(ShareItems)
        case legal(LegalDocument)

        var id: String {
            switch self {
            case .share(let items): "share-\(items.id.uuidString)"
            case .legal(let document): "legal-\(document.id)"
            }
        }
    }
    @State private var qa = BetaQA.shared

    var body: some View {
        @Bindable var store = store
        Form {
                    Section { AccountCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    Section("Ate Plus") {
                        NavigationLink {
                            AtePlusPaywallView()
                        } label: {
                            Label("Ate Plus", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("settings.atePlus")
                    }
                    card {
                        toggle("Private mode", "Keep everything local — no new AI generations, only your saved cards.",
                               $store.settings.onDeviceOnly)
                        Text(OnDeviceBackend.availabilityDescription).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    }
                    card {
                        Toggle(isOn: $journalingEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Journaling Suggestions").font(AteFont.body(16, .medium))
                                Text(JournalingSuggestionsGate.isAvailable
                                     ? "Pick a moment (photo, workout, place) in Insights and turn it into an Ate entry or recipe draft."
                                     : "Needs a paid Apple Developer build with Apple's Journaling Suggestions entitlement. Not available in this build.")
                                    .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.primary).disabled(!JournalingSuggestionsGate.isAvailable)
                        .accessibilityIdentifier("toggle.journalingSuggestions")
                    }
                    Section("Units") {
                        Picker("Units", selection: $store.settings.units) {
                            Text("Metric").tag(UnitSystem.metric); Text("Imperial").tag(UnitSystem.imperial)
                        }.pickerStyle(.segmented)
                    }
                    Section {
                        toggle("Sound", "Play a chime when a timer ends.", $store.timerPrefs.sound)
                        toggle("Vibration", "Buzz your device (where supported).", $store.timerPrefs.vibration)
                        toggle("Quiet hours", "Mute the chime during this window — vibration and alerts still work.",
                               $store.timerPrefs.quietHours)
                        if store.timerPrefs.quietHours {
                            HStack(spacing: 12) {
                                timePicker("From", $store.timerPrefs.quietStart)
                                timePicker("Until", $store.timerPrefs.quietEnd)
                            }
                        }
                        toggle("Step-by-step alerts", "Show a system notification for each step.", $store.timerPrefs.stepAlerts)
                    } header: { Text("Timer notifications") } footer: {
                        Text("Choose how ate lets you know a cook-mode step timer has finished.")
                    }
                    Section {
                        Button("Clear all", role: .destructive) { confirmClear = true }
                    } header: { Text("Your data") } footer: {
                        Text(store.session == nil
                             ? "Recipes are stored on this iPhone only. Sign in to sync them to your account."
                             : "Recipes and your shopping list sync to your ate account (Supabase, EU). Shared recipes are public to anyone with the link.")
                    }
                    if AppConfig.isBetaBuild {
                        Section("Beta & diagnostics") {
                            // This is the primary Beta entry on current builds. A direct
                            // destination avoids typed-path resolution after data resets.
                            NavigationLink {
                                BetaTestingView()
                            } label: {
                                Label("Beta testing", systemImage: "checklist")
                            }
                            .accessibilityIdentifier("settings.betaTesting")
                        }
                    }
                    Section("Diagnostics") {
                        NavigationLink {
                            DiagnosticHistoryView()
                        } label: {
                            Label("Diagnostic history", systemImage: "waveform.path")
                        }
                        .accessibilityIdentifier("settings.diagnosticHistory")
                    }
                    Section("Tools") {
                        Button { if let u = writeTemp("ate-recipes.json", store.exportJSON()) { activeSheet = .share(ShareItems(items: [u])) } } label: {
                            Label("Export data", systemImage: "arrow.down.doc")
                        }.accessibilityIdentifier("settings.export")
                        Button { importing = true } label: {
                            Label("Import recipes", systemImage: "square.and.arrow.down")
                        }.accessibilityIdentifier("settings.import")
                        Button { store.replayOnboarding() } label: {
                            Label("Replay intro", systemImage: "sparkles")
                        }.accessibilityIdentifier("settings.replayOnboarding")
                    }
                    Section {
                        Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))" + (AppConfig.channel.isEmpty ? "" : " · \(AppConfig.channel)"))
                            .accessibilityIdentifier("aboutVersion")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Changes in this build").font(AteFont.body(12, .semibold))
                            Text(BuildNotes.current)
                                .font(AteFont.body(12))
                                .foregroundStyle(Theme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("aboutBuildNotes")
                        }
                        .textSelection(.enabled)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("aboutBuildNotesSection")
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
                        if AppConfig.privacyURL != nil {
                            Button { activeSheet = .legal(.privacy) } label: {
                                Label("Privacy Policy", systemImage: "hand.raised")
                            }.accessibilityIdentifier("settingsPrivacy")
                        }
                        if AppConfig.termsURL != nil {
                            Button { activeSheet = .legal(.terms) } label: {
                                Label("Terms of Use", systemImage: "doc.text")
                            }.accessibilityIdentifier("settingsTerms")
                        }
                    } header: { Text("About") } footer: {
                        Text(Transparency.ai).accessibilityIdentifier("aiTransparency")
                    }
                    Section { Button {
                        UIPasteboard.general.string = AppConfig.versionLine
                        store.show("Version info copied")
                    } label: {
                        Text(AppConfig.versionLine).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("versionFooter").accessibilityHint("Copies version info")
                    }.listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        // Let the last rows scroll fully clear of the floating tab bar instead of sitting under it.
        .contentMargins(.bottom, 96, for: .scrollContent)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .navigationTitle("Settings")
        .ateRootNavigationChrome(logoID: "settings.logo")
        .onChange(of: store.timerPrefs.stepAlerts) { _, on in if on { Task { _ = await TimerAlerts.requestPermission() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let n = try store.importJSON(try Data(contentsOf: url))
                store.show(n > 0 ? "Imported \(n) recipe\(n == 1 ? "" : "s")" : "Library up to date")
            } catch { store.show("That file isn't a ate export.", error: true) }
        }
        .confirmationDialog("Clear your whole library?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { store.clearLibrary(); store.show("Library cleared") }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share(let items):
                ActivityView(items: items.items).presentationDetents([.medium, .large])
            case .legal(let document):
                if let url = document.url {
                    LegalDocumentSheet(title: document.title, url: url)
                }
            }
        }
        .onChange(of: qa.openRequested, initial: true) { _, requested in
            guard requested else { return }
            qa.openRequested = false
            guard AppConfig.isBetaBuild else { return }
            store.select(.settings)
            Task { @MainActor in
                await Task.yield()
                guard store.tab == .settings else { return }
                store.settingsPath = [.beta]
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View { Section { c() } }

    private func toggle(_ title: String, _ detail: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AteFont.body(16, .medium))
                Text(detail).font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            }
        }.tint(Theme.primary).accessibilityIdentifier("toggle." + title)
    }

    private func timePicker(_ label: String, _ b: Binding<String>) -> some View {
        let date = Binding<Date>(
            get: {
                let m = TimerAlerts.minutes(b.wrappedValue)
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                b.wrappedValue = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            })
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(AteFont.body(13, .medium)).foregroundStyle(Theme.mutedForeground)
            DatePicker(label, selection: date, displayedComponents: .hourAndMinute).labelsHidden()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
