import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var exporting = false
    @AppStorage(JournalingSuggestionsGate.settingKey) private var journalingEnabled = false
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiStatus = SettingsAIStatus.current
    @State private var importing = false
    @State private var confirmingImport = false
    @State private var pendingImportData: Data?
    @State private var confirmClear = false
    @State private var activeSheet: SettingsSheet?

    private enum SettingsSheet: Identifiable {
        case share(ShareItems)
        case legal(LegalDocument)

        var id: String {
            switch self {
            case .share(let items):
                return "share-\(items.id.uuidString)"
            case .legal(let document):
                return "legal-\(document.id)"
            }
        }
    }
    @State private var qa = BetaQA.shared

    var body: some View {
        @Bindable var store = store
        Form {
                    Section {
                        // Keep the sync summary in the same content row as the account card.
                        // Form section footers expose a non-resizable SwiftUI accessibility
                        // node on iOS 27, which fails the Dynamic Type audit even though the
                        // underlying Text uses a scalable system style.
                        VStack(alignment: .leading, spacing: 10) {
                            AccountCard()
                            Text(SettingsCopy.syncSummary(accountAvailable: store.accountAvailable,
                                                          signedIn: store.session != nil))
                                .font(.footnote)
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.horizontal, 20)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("settings.syncSummary")
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    Section("Ate Plus") {
                        NavigationLink {
                            AtePlusPaywallView()
                        } label: {
                            Label("Ate Plus", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("settings.atePlus")
                    }
                    Section {
                        toggle("Private mode", "Keep everything local — no new AI generations, only your saved cards.",
                               $store.settings.onDeviceOnly)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-device AI").font(AteFont.body(12, .semibold))
                            Text(SettingsCopy.aiStatusTitle(privateMode: store.settings.onDeviceOnly,
                                                            status: aiStatus))
                                .font(.footnote.weight(.semibold))
                            Text(SettingsCopy.aiStatusGuidance(privateMode: store.settings.onDeviceOnly,
                                                               status: aiStatus))
                            Text(SettingsCopy.aiExplanation)
                        }
                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.aiAvailability")
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
                    } header: {
                        Text("AI on this device")
                    }
                    Section {
                        NavigationLink(value: Route.nutritionDiary) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Food diary")
                                    Text("What you ate, day by day.")
                                        .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
                                }
                            } icon: { Image(systemName: "fork.knife") }
                        }
                        .accessibilityIdentifier("settings.nutritionDiary")
                        NavigationLink(value: Route.nutritionGoals) {
                            Label("Nutrition goals", systemImage: "target")
                        }
                        .accessibilityIdentifier("settings.nutritionGoals")
                    } header: {
                        Text("Nutrition")
                    } footer: {
                        Text(SettingsCopy.nutritionFooter)
                    }
                    Section {
                        Picker("Appearance", selection: $store.settings.appearance) {
                            ForEach(AppAppearance.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.appearance")
                    } header: { Text("Appearance") } footer: {
                        Text("System follows your iPhone's appearance. Light or Dark applies to Ate. Widgets and Live Activities keep their current appearance.")
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
                        Text(SettingsCopy.dataFooter(signedIn: store.session != nil))
                    }
                    Section {
                        Button {
                            guard !exporting else { return }
                            exporting = true
                            Task { @MainActor in
                                defer { exporting = false }
                                do {
                                    let data = try await store.exportUserData()
                                    guard let url = writeTemp("ate-data.json", data) else {
                                        store.show("Your data export couldn't be created. Please try again.", error: true)
                                        return
                                    }
                                    activeSheet = .share(ShareItems(items: [url]))
                                } catch {
                                    store.show("Your data couldn't be exported. Please try again.", error: true)
                                }
                            }
                        } label: {
                            Label(exporting ? "Preparing export..." : "Export data", systemImage: "arrow.down.doc")
                        }
                        .disabled(exporting)
                        .accessibilityIdentifier("settings.export")
                        Button { importing = true } label: {
                            Label("Import data", systemImage: "square.and.arrow.down")
                        }.accessibilityIdentifier("settings.import")
                        Button { store.replayOnboarding() } label: {
                            Label("Replay intro", systemImage: "sparkles")
                        }.accessibilityIdentifier("settings.replayOnboarding")
                    } header: { Text("Tools") } footer: {
                        Text(SettingsCopy.toolsFooter)
                    }
                    // Everyday settings end above this point. Developer and beta surfaces
                    // are grouped together at the bottom, just before About.
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

                            NavigationLink {
                                BetaFeedbackView()
                            } label: {
                                Label("Share Feedback", systemImage: "message.badge")
                            }
                            .accessibilityIdentifier("settings.shareFeedback")
                        }
                    }
                    Section("Product") {
                        NavigationLink { ProductReleaseNotesView() } label: {
                            Label("Release Notes", systemImage: "doc.text")
                        }.accessibilityIdentifier("settings.releaseNotes")
                    }
                    Section("Diagnostics") {
                        NavigationLink {
                            DiagnosticHistoryView()
                        } label: {
                            Label("Diagnostic history", systemImage: "waveform.path")
                        }
                        .accessibilityIdentifier("settings.diagnosticHistory")
                    }
                    Section {
                        Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))" + (AppConfig.channel.isEmpty ? "" : " · \(AppConfig.channel)"))
                            .accessibilityIdentifier("aboutVersion")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Changes in this build").font(AteFont.body(12, .semibold))
                                .accessibilityIdentifier("aboutBuildNotesHeading")
                            Text(BuildNotes.current)
                                .font(AteFont.body(12))
                                .foregroundStyle(Theme.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("aboutBuildNotes")
                        }
                        .textSelection(.enabled)
                        // Keep the short heading independently addressable when notes span
                        // more than one screen. The full selectable body remains unchanged.
                        .accessibilityElement(children: .contain)
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
        // Bridge the Insights shortcut onto the typed path so the push is recorded in
        // settingsPath (isAtTabRoot -> false, root-only bottom accessory stays off, #179).
        .onChange(of: store.showNutritionDiary) { _, show in
            if show { store.settingsPath.append(Route.nutritionDiary); store.showNutritionDiary = false }
        }
        .ateRootNavigationChrome(logoID: "settings.logo")
        .onAppear {
            store.bottomAddContext = .recipe
            aiStatus = SettingsAIStatus.current
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { aiStatus = SettingsAIStatus.current }
        }
        .onChange(of: store.timerPrefs.stepAlerts) { _, on in if on { Task { _ = await TimerAlerts.requestPermission() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImportData = try Data(contentsOf: url)
                confirmingImport = true
            } catch { store.show("That file couldn’t be read. Please try again.", error: true) }
        }
        .confirmationDialog("Import this data backup?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Import data") { importSelectedData() }
            Button("Cancel", role: .cancel) { pendingImportData = nil }
        } message: {
            Text("New recipes, shopping items and diary entries will be added. Existing matching items stay on this iPhone. If this archive contains nutrition goals and app preferences, they replace the current ones.")
        }
        .confirmationDialog("Clear your whole library?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) { Task { if await store.clearLibrary() { store.show("Library cleared") } } }
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

    private func importSelectedData() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            store.show(try store.importJSON(data).message)
        } catch let error as AteDataArchiveError {
            store.show(error.localizedDescription, error: true)
        } catch {
            store.show("That file isn’t a supported ate data export.", error: true)
        }
    }

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
