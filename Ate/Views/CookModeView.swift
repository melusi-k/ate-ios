import SwiftUI

struct CookModeView: View {
    let recipeID: String
    var onExit: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var index = 0
    @State private var showIngredients = false
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
        .toolbar(.visible, for: .bottomBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Opening Cook Mode is intent, not evidence that a meal was cooked.
            // Record history only when the user explicitly finishes the final step.
            // Resume at the step whose timer is running, if any.
            if let session = store.cookSession, session.recipeID == recipeID {
                index = session.stepIndex
            }
            if let t = store.timers.timers.first(where: { $0.recipeID == recipeID && $0.isRunning }) { index = t.stepIndex }
            store.updateCookSession(recipeID: recipeID, stepIndex: index)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; voice.stop() }
        .onChange(of: index) {
            store.updateCookSession(recipeID: recipeID, stepIndex: index)
            Haptics.step()
        }
    }

    private func exit() {
        store.timers.cleanupIdle(recipeID: recipeID)
        if let onExit { onExit() } else if !store.path.isEmpty { store.path.removeLast() }
    }

    /// "4 minutes 12 seconds" for VoiceOver instead of "4:12".
    static func spoken(_ secs: Int) -> String {
        let f = DateComponentsFormatter(); f.unitsStyle = .full; f.allowedUnits = secs >= 3600 ? [.hour, .minute] : [.minute, .second]
        return f.string(from: TimeInterval(max(0, secs))) ?? "\(secs) seconds"
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
                Button(action: exit) { Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.ate(.ghost, height: 44)).accessibilityLabel("Exit")   // design review: icon-only ✕
                Button { showIngredients = true } label: { Image(systemName: "list.bullet").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.ate(.ghost, height: 44))
                    .accessibilityLabel("Ingredients")
                    .accessibilityHint("Shows the ingredient checklist, scaled to your servings")
                    .accessibilityIdentifier("cookIngredientsButton")
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
                        Text("“\(voice.lastHeard.suffix(60))”").font(AteFont.body(12)).foregroundStyle(Theme.warmForeground)
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
            .frame(height: 6).animation(Motion.anim(.easeInOut), value: index)
            .accessibilityElement().accessibilityLabel("Progress").accessibilityValue("Step \(index + 1) of \(n)")

            ForEach(others) { t in
                Button { index = t.stepIndex } label: {
                    Label("Step \(t.stepIndex + 1) · \(format(t.remaining(at: store.timers.now)))", systemImage: "timer")
                        .font(AteFont.body(13, .semibold)).monospacedDigit()
                }.buttonStyle(.ate(.secondary, height: 44))
                .accessibilityLabel("Go to step \(t.stepIndex + 1), \(Self.spoken(t.remaining(at: store.timers.now))) left")
            }

            Spacer()
            Text(Units.convertTemperatures(in: s.instruction, to: store.settings.units))
                .font(AteFont.display(UIScreen.main.bounds.width > 400 ? 34 : 30)).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("Step \(index + 1) of \(n). " + Units.convertTemperatures(in: s.instruction, to: store.settings.units))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("cookStepText")
            if let range = Durations.rangeLabel(in: s.instruction), (s.timeSeconds ?? 0) > 0 {
                Text("\(range) · timer set to the longer time").font(AteFont.body(13)).foregroundStyle(Theme.warmForeground)
                    .accessibilityIdentifier("cookTimerRange")
            }
            if let secs = s.timeSeconds, secs > 0 {
                let running = active?.isRunning == true
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Theme.primary).font(.title2)
                        Text(format(remaining)).font(.largeTitle.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                            .accessibilityIdentifier("cookTimerValue")
                            .accessibilityValue(Self.spoken(remaining) + (running ? " remaining" : ", paused"))
                            .accessibilityAddTraits(.updatesFrequently)
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
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
        .pageWidth()
        .sheet(isPresented: $showIngredients) {
            CookIngredientsSheet(recipe: recipe).environment(store)
        }
        .toolbar {
            // Back / Next live in the system bottom toolbar (bottom-bar semantics, glass on iOS 26).
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Back") { index -= 1 }.disabled(index == 0).frame(minHeight: 44)
                Spacer()
                if index < n - 1 {
                    Button("Next step") { index += 1 }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("cookNextStep")
                } else {
                    Button("Finish cooking") {
                        DiagnosticHistory.shared.record(.cookingSessionCompleted)
                        store.markCooked(recipeID)
                        store.clearCookSession(recipeID: recipeID)
                        exit()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("cookFinish")
                }
            }
        }
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


/// Compact session entry point shown after leaving Cook Mode. It is intentionally independent of timer existence.
struct CookSessionMiniPlayer: View {
    @Environment(AppStore.self) private var store
    let session: CookSession

    var body: some View {
        if let recipe = store.recipe(session.recipeID), !recipe.steps.isEmpty {
            Button {
                store.updateCookSession(recipeID: session.recipeID, stepIndex: session.stepIndex)
                store.cookTarget = CookTarget(id: session.recipeID)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "frying.pan").foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recipe.title).font(AteFont.body(13, .semibold)).lineLimit(2)
                        // Two lines at accessibility sizes: one line truncated the step
                        // text inside the capsule at AX5 (CI pixel evidence, #179).
                        Text("Resume · Step \(min(session.stepIndex, recipe.steps.count - 1) + 1) of \(recipe.steps.count)")
                            .font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 14)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.foreground)
            .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
            .accessibilityIdentifier("cookSessionMiniPlayer")
            .accessibilityLabel("Resume cooking \(recipe.title)")
            .accessibilityValue("Step \(min(session.stepIndex, recipe.steps.count - 1) + 1) of \(recipe.steps.count)")
            .accessibilityHint("Returns to your saved cooking step")
            .contextMenu {
                Button("End cooking session", role: .destructive) {
                    store.clearCookSession(recipeID: session.recipeID)
                }
            }
        }
    }
}

/// Sticky timer summary: one bar no matter how many timers run. One timer shows inline controls;
/// two or more collapse to "N timers · next 04:12", which opens a half sheet with every timer.
struct TimerBar: View {
    @Environment(AppStore.self) private var store
    @State private var showAll = false
    var body: some View {
        let timers = store.timers.timers
        Group {
            if timers.count == 1, let t = timers.first {
                TimerRow(t: t)
            } else if !timers.isEmpty {
                let next = timers.filter(\.isRunning).map { $0.remaining(at: store.timers.now) }.min()
                Button { showAll = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Theme.primary)
                        Text("\(timers.count) timers").font(AteFont.body(15, .semibold))
                        Spacer(minLength: 4)
                        if let next { Text("next " + TimerRow.mmss(next)).font(.title3.weight(.bold)).fontDesign(.rounded).monospacedDigit() }
                        Image(systemName: "chevron.up").foregroundStyle(Theme.mutedForeground)
                    }
                    .frame(minHeight: 44).padding(.horizontal, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.foreground)
                .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                .shadow(color: Theme.brown.opacity(0.15), radius: 10, y: 4)
                .accessibilityIdentifier("timerBarSummary")
                .accessibilityLabel("\(timers.count) timers").accessibilityValue(next.map { "next ends in " + CookModeView.spoken($0) } ?? "all paused").accessibilityHint("Shows all timers")
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timerBar")
        .sheet(isPresented: $showAll) {
            NavigationStack {
                List(store.timers.timers) { t in TimerRow(t: t, chrome: false).listRowBackground(Theme.card) }
                    .navigationTitle("Timers").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAll = false } } }
            }
            .presentationDetents([.medium, .large])
            .onChange(of: store.timers.timers.count) { _, n in if n < 2 { showAll = false } }
            .onChange(of: store.cookTarget) { _, t in if t != nil { showAll = false } }
        }
    }
}

struct TimerRow: View {
    @Environment(AppStore.self) private var store
    let t: ActiveTimer
    var chrome = true
    static func mmss(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
    var body: some View {
        let row = HStack(spacing: 10) {
            Button { if store.recipe(t.recipeID) != nil { store.cookTarget = CookTarget(id: t.recipeID) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: t.isRunning ? "timer" : "pause.circle").foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.recipeTitle).font(AteFont.body(13, .semibold)).lineLimit(2)
                        Text((t.recipeID == TimerMath.quickRecipeID ? "Quick timer" : "Step \(t.stepIndex + 1)") + (t.isRunning ? "" : " · paused")).font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: 4)
                    Text(Self.mmss(t.remaining(at: store.timers.now))).font(.title3.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timerBarOpen")
            .accessibilityLabel("Open cook mode for \(t.recipeTitle)")
            .accessibilityValue("Step \(t.stepIndex + 1), " + CookModeView.spoken(t.remaining(at: store.timers.now)) + (t.isRunning ? " left" : ", paused"))
            .accessibilityHint("Opens cook mode at this step")
            IconButton(symbol: t.isRunning ? "pause.fill" : "play.fill", label: t.isRunning ? "Pause bar timer" : "Resume bar timer") {
                store.timers.toggle(t.id)
            }
            IconButton(symbol: "stop.fill", label: "Stop bar timer", tint: Theme.destructive) { store.timers.stop(t.id) }
        }
        .foregroundStyle(Theme.foreground)
        if chrome {
            row.padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
                .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                .shadow(color: Theme.brown.opacity(0.15), radius: 10, y: 4)
        } else { row }
    }
}
