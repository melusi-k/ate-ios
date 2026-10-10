import SwiftUI

struct CookModeView: View {
    let recipeID: String
    var onExit: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var index = 0
    @State private var voice = VoiceController()
    @State private var testUtterance = ""

    init(recipeID: String, onExit: (() -> Void)? = nil) {
        self.recipeID = recipeID
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Theme.warm.ignoresSafeArea()
            if let recipe = store.recipe(recipeID), !recipe.steps.isEmpty {
                content(recipe)
            } else {
                RecipeNotFoundView(title: "Nothing to cook here", onBack: exit)
            }
        }
        .foregroundStyle(Theme.warmForeground)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            store.markCooked(recipeID)
            // Resume at the step whose timer is running, if any.
            if let t = store.timers.timers.first(where: { $0.recipeID == recipeID && $0.isRunning }) { index = t.stepIndex }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; voice.stop() }
        .onChange(of: index) { Haptics.step() }
    }

    private func exit() {
        store.timers.cleanupIdle(recipeID: recipeID)
        if let onExit { onExit() } else if !store.path.isEmpty { store.path.removeLast() }
    }

    private func step(_ r: RecipeCard) -> Step { r.steps[min(index, r.steps.count - 1)] }

    @ViewBuilder private func content(_ recipe: RecipeCard) -> some View {
        let n = recipe.steps.count
        let s = step(recipe)
        let active = store.timers.timer(recipeID, min(index, n - 1))
        let remaining = active?.remaining(at: store.timers.now) ?? (s.timeSeconds ?? 0)
        let others = store.timers.timers.filter { $0.recipeID == recipeID && $0.stepIndex != index && $0.isRunning }
        VStack(spacing: 20) {
            HStack {
                Button(action: exit) { Label("Exit", systemImage: "chevron.left") }.buttonStyle(.ate(.ghost, height: 44))
                Spacer()
                Text("Step \(index + 1) of \(n)").font(AteFont.body(14, .medium))
                Button {
                    voice.onCommand = { handle($0, recipe) }
                    voice.toggle()
                } label: { Image(systemName: voice.isListening ? "mic.fill" : "mic") }
                    .buttonStyle(.ate(voice.isListening ? .primary : .secondary, height: 44))
                    .accessibilityLabel(voice.isListening ? "Stop voice control" : "Start voice control")
                    .accessibilityIdentifier("voiceToggle")
            }
            if voice.isListening {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.voiceListening, systemImage: "waveform").font(AteFont.body(13, .semibold))
                    if !voice.lastHeard.isEmpty {
                        Text("“\(voice.lastHeard.suffix(60))”").font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
                            .accessibilityIdentifier("voiceHeard")
                    }
                    if AppConfig.isUITesting {
                        TextField("say…", text: $testUtterance).accessibilityIdentifier("voiceTestInput")
                            .onSubmit { voice.heard(testUtterance) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain).accessibilityIdentifier("voicePanel")
            } else if case .unavailable(let why) = voice.state {
                Text(why).font(AteFont.body(13)).foregroundStyle(Theme.destructive).accessibilityIdentifier("voiceUnavailable")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.warmForeground.opacity(0.15))
                    Capsule().fill(Theme.primary).frame(width: g.size.width * CGFloat(index + 1) / CGFloat(n))
                }
            }
            .frame(height: 6).animation(.easeInOut, value: index)

            ForEach(others) { t in
                Button { index = t.stepIndex } label: {
                    Label("Step \(t.stepIndex + 1) · \(format(t.remaining(at: store.timers.now)))", systemImage: "timer")
                        .font(AteFont.body(13, .semibold)).monospacedDigit()
                }.buttonStyle(.ate(.secondary, height: 32))
            }

            Spacer()
            Text(Units.convertTemperatures(in: s.instruction, to: store.settings.units))
                .font(AteFont.display(UIScreen.main.bounds.width > 400 ? 34 : 30)).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.5)
            if let secs = s.timeSeconds, secs > 0 {
                let running = active?.isRunning == true
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Theme.primary).font(.system(size: 24))
                        Text(format(remaining)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("cookTimerValue")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        if let a = active { store.timers.toggle(a.id) } else { store.timers.start(recipe: recipe, stepIndex: index) }
                    } label: { Image(systemName: running ? "pause.fill" : "play.fill") }
                        .buttonStyle(.ate(.primary, height: 52)).accessibilityLabel(running ? "Pause timer" : "Start timer")
                    Button { if let a = active { store.timers.reset(a.id) } } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.ate(.secondary, height: 52)).accessibilityLabel("Reset timer")
                }
                .foregroundStyle(Theme.foreground)
            }
            Spacer()
            HStack(spacing: 12) {
                Button("Back") { index -= 1 }
                    .buttonStyle(.ate(.secondary, height: 56, full: true)).disabled(index == 0)
                Button("Next step") { index += 1 }
                    .buttonStyle(.ate(.primary, height: 56, full: true)).disabled(index >= n - 1)
                    .layoutPriority(1).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 32)
        .pageWidth()
    }

    private func format(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func handle(_ cmd: VoiceCommand, _ recipe: RecipeCard) {
        let n = recipe.steps.count
        switch cmd {
        case .next: if index < n - 1 { index += 1; voice.speak(stepSpeech(recipe)) }
        case .back: if index > 0 { index -= 1; voice.speak(stepSpeech(recipe)) }
        case .repeatStep: voice.speak(stepSpeech(recipe))
        case .startTimer:
            guard (step(recipe).timeSeconds ?? 0) > 0 else { voice.speak("This step has no timer."); return }
            if let a = store.timers.timer(recipeID, index) { if !a.isRunning { store.timers.toggle(a.id) } }
            else { store.timers.start(recipe: recipe, stepIndex: index) }
            store.show("Timer started")
        case .pauseTimer:
            if let a = store.timers.timer(recipeID, index), a.isRunning { store.timers.toggle(a.id) }
        case .exit: exit()
        }
    }

    private func stepSpeech(_ r: RecipeCard) -> String {
        "Step \(index + 1). " + Units.convertTemperatures(in: step(r).instruction, to: store.settings.units)
    }
}

/// Sticky bar showing running/paused cook timers on every screen outside cook mode.
struct TimerBar: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.timers.timers) { t in
                HStack(spacing: 10) {
                    Button { store.cookTarget = CookTarget(id: t.recipeID) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.isRunning ? "timer" : "pause.circle").foregroundStyle(Theme.primary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.recipeTitle).font(AteFont.body(13, .semibold)).lineLimit(1)
                                Text("Step \(t.stepIndex + 1)" + (t.isRunning ? "" : " · paused")).font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                            }
                            Spacer(minLength: 4)
                            Text(String(format: "%d:%02d", t.remaining(at: store.timers.now) / 60, t.remaining(at: store.timers.now) % 60))
                                .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timerBarOpen")
                    .accessibilityLabel("Open cook mode for \(t.recipeTitle)")
                    IconButton(symbol: t.isRunning ? "pause.fill" : "play.fill", label: t.isRunning ? "Pause bar timer" : "Resume bar timer") {
                        store.timers.toggle(t.id)
                    }
                    IconButton(symbol: "stop.fill", label: "Stop bar timer", tint: Theme.destructive) { store.timers.stop(t.id) }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.border))
                .shadow(color: Theme.brown.opacity(0.15), radius: 10, y: 4)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timerBar")
    }
}
