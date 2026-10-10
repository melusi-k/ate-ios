import SwiftUI
import Combine

struct CookModeView: View {
    let recipeID: String
    var onExit: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var index = 0
    @State private var remaining = 0
    @State private var endDate: Date?
    @State private var primed = false
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; resetTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; TimerAlerts.cancel() }
        .onReceive(tick) { _ in tickTimer() }
    }

    private func exit() { if let onExit { onExit() } else { store.path.removeLast() } }

    private func step(_ r: RecipeCard) -> Step { r.steps[min(index, r.steps.count - 1)] }

    @ViewBuilder private func content(_ recipe: RecipeCard) -> some View {
        let n = recipe.steps.count
        let s = step(recipe)
        VStack(spacing: 20) {
            HStack {
                Button(action: exit) { Label("Exit", systemImage: "chevron.left") }.buttonStyle(.ate(.ghost, height: 44))
                Spacer()
                Text("Step \(index + 1) of \(n)").font(AteFont.body(14, .medium))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.warmForeground.opacity(0.15))
                    Capsule().fill(Theme.primary).frame(width: g.size.width * CGFloat(index + 1) / CGFloat(n))
                }
            }
            .frame(height: 6).animation(.easeInOut, value: index)

            Spacer()
            Text(Units.convertTemperatures(in: s.instruction, to: store.settings.units))
                .font(AteFont.display(UIScreen.main.bounds.width > 400 ? 34 : 30)).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.5)
            if let secs = s.timeSeconds, secs > 0 {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Theme.primary).font(.system(size: 24))
                        Text(format(remaining)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    Button { Task { await toggleTimer(recipe) } } label: {
                        Image(systemName: endDate == nil ? "play.fill" : "pause.fill")
                    }.buttonStyle(.ate(.primary, height: 52)).accessibilityLabel(endDate == nil ? "Start timer" : "Pause timer")
                    Button { resetTimer() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.ate(.secondary, height: 52)).accessibilityLabel("Reset timer")
                }
                .foregroundStyle(Theme.foreground)
            }
            Spacer()
            HStack(spacing: 12) {
                Button("Back") { index -= 1; resetTimer() }
                    .buttonStyle(.ate(.secondary, height: 56, full: true)).disabled(index == 0)
                Button("Next step") { index += 1; resetTimer() }
                    .buttonStyle(.ate(.primary, height: 56, full: true)).disabled(index >= n - 1)
                    .layoutPriority(1).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 32)
        .pageWidth()
    }

    private func format(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func resetTimer() {
        endDate = nil
        TimerAlerts.cancel()
        if let r = store.recipe(recipeID), !r.steps.isEmpty { remaining = step(r).timeSeconds ?? 0 } else { remaining = 0 }
    }

    private func toggleTimer(_ recipe: RecipeCard) async {
        if endDate != nil {
            if let e = endDate { remaining = max(0, Int(ceil(e.timeIntervalSinceNow))) }
            endDate = nil
            TimerAlerts.cancel()
            return
        }
        if !primed, store.timerPrefs.stepAlerts { _ = await TimerAlerts.requestPermission(); primed = true }
        if remaining <= 0 { remaining = step(recipe).timeSeconds ?? 0 }
        let end = Date().addingTimeInterval(TimeInterval(remaining))
        endDate = end
        TimerAlerts.schedule(step: index + 1, recipeTitle: recipe.title, at: end, prefs: store.timerPrefs)
    }

    private func tickTimer() {
        guard let e = endDate else { return }
        remaining = max(0, Int(ceil(e.timeIntervalSinceNow)))
        if remaining == 0 {
            endDate = nil
            TimerAlerts.timerFinished(prefs: store.timerPrefs)
        }
    }
}
