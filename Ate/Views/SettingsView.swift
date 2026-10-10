import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var importing = false
    @State private var confirmClear = false
    @State private var share: ShareItems?

    var body: some View {
        @Bindable var store = store
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings").font(AteFont.display(30))

                    AccountCard()
                    card {
                        toggle("Private mode", "Keep everything local — no new AI generations, only your saved cards.",
                               $store.settings.onDeviceOnly)
                        Text(OnDeviceBackend.availabilityDescription).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                    }
                    card {
                        Text("Units").font(AteFont.body(16, .semibold))
                        Picker("Units", selection: $store.settings.units) {
                            Text("Metric").tag(UnitSystem.metric); Text("Imperial").tag(UnitSystem.imperial)
                        }.pickerStyle(.segmented)
                    }
                    card {
                        Text("Timer notifications").font(AteFont.display(18))
                        Text("Choose how ate lets you know a cook-mode step timer has finished.")
                            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                        toggle("Sound", "Play a chime when a timer ends.", $store.timerPrefs.sound)
                        toggle("Vibration", "Buzz your device (where supported).", $store.timerPrefs.vibration)
                        toggle("Step-by-step alerts", "Show a system notification for each step.", $store.timerPrefs.stepAlerts)
                        Divider()
                        toggle("Quiet hours", "Mute the chime during this window — vibration and alerts still work.",
                               $store.timerPrefs.quietHours)
                        if store.timerPrefs.quietHours {
                            HStack(spacing: 12) {
                                timePicker("From", $store.timerPrefs.quietStart)
                                timePicker("Until", $store.timerPrefs.quietEnd)
                            }
                        }
                    }
                    card {
                        Text("About").font(AteFont.display(18))
                        Button { store.replayOnboarding() } label: { Label("Replay intro", systemImage: "sparkles") }
                            .buttonStyle(.ate(.secondary, height: 40)).accessibilityIdentifier("replayOnboarding")
                        HStack(spacing: 16) {
                            if let u = AppConfig.privacyURL { Link("Privacy Policy", destination: u).accessibilityIdentifier("settingsPrivacy") }
                            if let u = AppConfig.termsURL { Link("Terms of Use", destination: u).accessibilityIdentifier("settingsTerms") }
                        }.font(AteFont.body(14, .medium)).tint(Theme.primary)
                        Text("Version \(AppConfig.appVersion) (build \(AppConfig.buildNumber))")
                            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground).accessibilityIdentifier("aboutVersion")
                    }
                    card {
                        Text("Your data").font(AteFont.display(18))
                        Text("Recipes are stored on this device only. Nothing is uploaded when you browse or cook.")
                            .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                        WrapLayout(spacing: 8) {
                            Button { if let u = writeTemp("ate-recipes.json", store.exportJSON()) { share = ShareItems(items: [u]) } } label: {
                                Label("Export data", systemImage: "arrow.down.doc")
                            }.buttonStyle(.ate(.secondary, height: 40))
                            Button { importing = true } label: { Label("Import recipes", systemImage: "square.and.arrow.down") }
                                .buttonStyle(.ate(.secondary, height: 40))
                            Button("Clear all") { confirmClear = true }.buttonStyle(.ate(.destructiveGhost, height: 40))
                        }
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8)
                .pageWidth()

                Button {
                    UIPasteboard.general.string = AppConfig.versionLine
                    store.show("Version info copied")
                } label: {
                    Text(AppConfig.versionLine).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .accessibilityIdentifier("versionFooter").accessibilityHint("Copies version info")
                .pageWidth()
            }
        }
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
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { c() }.frame(maxWidth: .infinity, alignment: .leading).cardSurface(padding: 20)
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
