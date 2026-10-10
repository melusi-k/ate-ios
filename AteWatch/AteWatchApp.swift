import SwiftUI
import WatchKit

@main
struct AteWatchApp: App {
    @State private var store = WatchStore()
    @State private var wrist = WristTimer()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(wrist)
        }
    }
}

let ateOrange = Color(red: 0xC9 / 255, green: 0x50 / 255, blue: 0x28 / 255)

struct RootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WristTimer.self) private var wrist
    var body: some View {
        NavigationStack {
            List {
                if let t = wrist.timer {
                    Section("Timer") { TimerRow(timer: t) }
                }
                if let c = store.phoneCook.first {
                    Section("Cooking on iPhone") {
                        VStack(alignment: .leading) {
                            Text(c.recipeTitle).font(.headline)
                            Text("Step \(c.stepIndex + 1) of \(c.stepCount)").font(.caption).foregroundStyle(.secondary)
                            if let end = c.timerEnd, end > Date() { Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().foregroundStyle(ateOrange) }
                        }
                    }
                }
                if store.signedIn {
                    NavigationLink { RecipeListView() } label: { Label("Recipes (\(store.recipes.count))", systemImage: "book") }
                    NavigationLink { ShoppingView() } label: { Label("Shopping", systemImage: "cart") }
                    Button("Sync now") { Task { await store.refresh() } }
                    Button("Sign out", role: .destructive) { store.signOut() }
                } else {
                    NavigationLink { SignInView() } label: { Label("Sign in", systemImage: "person.crop.circle") }
                    if !store.recipes.isEmpty { NavigationLink { RecipeListView() } label: { Label("Saved recipes", systemImage: "book") } }
                }
                if let s = store.status { Text(s).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("ate")
        }
        .tint(ateOrange)
        .task { await store.refresh() }
    }
}

struct TimerRow: View {
    @Environment(WristTimer.self) private var wrist
    let timer: WatchStepTimer
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(timer.recipeTitle).font(.caption).lineLimit(1)
                if let end = timer.endDate { Text(timerInterval: Date()...max(end, Date()), countsDown: true).font(.title3.bold()).monospacedDigit() }
                else { Text(WatchFormat.mmss(timer.pausedRemaining) + " paused").font(.title3.bold()).monospacedDigit() }
            }
            Spacer()
            Button { wrist.pauseResume() } label: { Image(systemName: timer.endDate == nil ? "play.fill" : "pause.fill") }
                .buttonStyle(.borderless)
        }
    }
}

struct SignInView: View {
    @Environment(WatchStore.self) private var store
    @State private var email = ""
    @State private var code = ""
    var body: some View {
        Form {
            if store.pendingEmail == nil {
                TextField("Email", text: $email).textContentType(.emailAddress)
                Button("Send code") { Task { await store.requestCode(email: email) } }
                    .disabled(!WatchAuthRequests.isPlausibleEmail(email))
                Text("Or open ate on your paired iPhone while signed in — the watch signs in automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                TextField("6-digit code", text: $code)
                Button("Verify") { Task { await store.verify(code: code) } }.disabled(!WatchAuthRequests.isValidCode(code))
            }
            if let s = store.status { Text(s).font(.footnote) }
        }
        .navigationTitle("Sign in")
    }
}

struct RecipeListView: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List(store.recipes) { r in
            NavigationLink { RecipeDetailWatch(recipe: r) } label: {
                VStack(alignment: .leading) {
                    Text(r.title).font(.headline).lineLimit(2)
                    if let m = r.timeMinutes { Text("\(m) min").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .overlay { if store.recipes.isEmpty { Text("No recipes yet. Add some on your iPhone.").multilineTextAlignment(.center).padding() } }
        .navigationTitle("Recipes")
    }
}

struct RecipeDetailWatch: View {
    let recipe: WatchRecipe
    var body: some View {
        List {
            if !recipe.steps.isEmpty {
                NavigationLink { CookModeWatch(recipe: recipe) } label: { Label("Cook", systemImage: "flame.fill").foregroundStyle(ateOrange) }
            }
            Section("Ingredients") { ForEach(recipe.ingredientLines, id: \.self) { Text($0).font(.footnote) } }
        }
        .navigationTitle(recipe.title)
    }
}

struct CookModeWatch: View {
    @Environment(WristTimer.self) private var wrist
    let recipe: WatchRecipe
    @State private var stepper: CookStepper
    @State private var crown: Double = 0
    init(recipe: WatchRecipe) { self.recipe = recipe; _stepper = State(initialValue: CookStepper(count: recipe.steps.count)) }

    var body: some View {
        let step = recipe.steps[stepper.index]
        VStack(spacing: 6) {
            Text(stepper.progressLabel).font(.caption2).foregroundStyle(ateOrange)
            ScrollView { Text(step.instruction).font(.title3).multilineTextAlignment(.leading) }
            if let secs = step.timeSeconds, secs > 0 {
                if let t = wrist.timer, t.stepIndex == stepper.index, t.recipeTitle == recipe.title { TimerRow(timer: t) }
                else { Button("Start \(WatchFormat.mmss(secs))") { wrist.start(title: recipe.title, step: stepper.index, seconds: secs) }.tint(ateOrange) }
            }
            HStack {
                Button { stepper.back(); crown = Double(stepper.index) } label: { Image(systemName: "chevron.left") }.disabled(!stepper.canGoBack)
                Button { stepper.next(); crown = Double(stepper.index) } label: { Image(systemName: "chevron.right") }.disabled(!stepper.canGoNext)
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: Double(max(0, recipe.steps.count - 1)), by: 1, sensitivity: .low)
        .onChange(of: crown) { _, v in
            let i = CookStepper.index(forCrown: v, count: recipe.steps.count)
            if i != stepper.index { stepper.index = i; WKInterfaceDevice.current().play(.click) }
        }
        .navigationTitle(recipe.title)
    }
}


struct ShoppingView: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List(store.shopping) { item in
            Button { Task { await store.toggle(item) } } label: {
                HStack {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? ateOrange : .secondary)
                    Text(WatchFormat.ingredient(.init(name: item.name, quantity: item.quantity, unit: item.unit)))
                        .strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                }
            }
        }
        .overlay { if store.shopping.isEmpty { Text("Shopping list is empty.").padding() } }
        .navigationTitle("Shopping")
    }
}
