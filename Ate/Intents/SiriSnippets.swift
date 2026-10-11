import AppIntents
import SwiftUI
import UIKit

// Siri answers with a card (snippet) and buttons, without opening ate.

struct ShoppingListSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on my shopping list"
    static let description = IntentDescription("Shows the next items on your ate shopping list, with tick buttons.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let items = SiriAnswers.openItems(AppStore.current?.shopping ?? [])
        QAProbe.shared.lastIntent = "list:\(items.count)"
        return .result(dialog: IntentDialog(stringLiteral: SiriAnswers.listLine(items)), view: ShoppingSnippet(items: Array(items.prefix(5))))
    }
}

struct TimerStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How long left on my timer"
    static let description = IntentDescription("Says how long is left on the next ate timer, with Pause and Stop.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let t = TimerMath.next(TimerSnapshot.load()) else {
            return .result(dialog: "No ate timers are running.", view: SnippetEmpty(text: "No timers"))
        }
        let rem = SiriAnswers.remaining(t)
        QAProbe.shared.lastIntent = "timer:\(rem)"
        let line = t.endDate == nil ? "\(t.recipeTitle) is paused with \(SiriAnswers.spoken(rem)) left."
                                    : "\(SiriAnswers.spoken(rem)) left on \(t.recipeTitle), step \(t.stepIndex + 1)."
        return .result(dialog: IntentDialog(stringLiteral: line), view: TimerSnippet(t: t))
    }
}

struct QuickRecipesIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick recipes"
    static let description = IntentDescription("Suggests three recipes you can cook in 30 minutes or less.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[RecipeAppEntity]> & ProvidesDialog & ShowsSnippetView {
        let quick = SiriAnswers.quick(AppStore.current?.recipes ?? [])
        QAProbe.shared.lastIntent = "quick:\(quick.count)"
        let line = quick.isEmpty ? "None of your ate recipes take under 30 minutes."
            : "You could make " + ListFormatter.localizedString(byJoining: quick.map(\.title)) + "."
        return .result(value: quick.map(RecipeAppEntity.init), dialog: IntentDialog(stringLiteral: line),
                       view: QuickSnippet(recipes: quick))
    }
}

/// Pure helpers (unit-tested).
enum SiriAnswers {
    /// "Tonight's pick is X. Why." with tidy spacing, capitalisation and a single full stop.
    static func pickLine(title: String, health: String?, why: String) -> String {
        func tidy(_ x: String) -> String {
            var t = x.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            while let l = t.last, ".!? ".contains(l) { t.removeLast() }
            return t
        }
        let lead = health.map { "It's a \(tidy($0).lowercased()), so tonight's pick is " } ?? "Tonight's pick is "
        let w = tidy(why)
        return lead + tidy(title) + "." + (w.isEmpty ? "" : " " + w.prefix(1).uppercased() + w.dropFirst() + ".")
    }
    static func openItems(_ s: [ShoppingItem]) -> [ShoppingItem] { s.filter { !$0.done } }
    static func listLine(_ items: [ShoppingItem]) -> String {
        guard !items.isEmpty else { return "Your ate shopping list is empty." }
        let top = items.prefix(3).map(\.name)
        let more = items.count > 3 ? ", and \(items.count - 3) more" : ""
        return "You need " + ListFormatter.localizedString(byJoining: Array(top)) + more + "."
    }
    static func quick(_ r: [RecipeCard], limit: Int = 30) -> [RecipeCard] {
        Array(r.filter { Durations.plausibleQuickMinutes($0).map { $0 <= limit } ?? false }
            .sorted { ($0.favorite ? 0 : 1, $0.timeMinutes ?? 0) < ($1.favorite ? 0 : 1, $1.timeMinutes ?? 0) }.prefix(3))
    }
    static func remaining(_ t: TimerSnapshot, now: Date = Date()) -> Int {
        t.endDate.map { max(0, Int($0.timeIntervalSince(now).rounded())) } ?? t.pausedRemaining
    }
    static func spoken(_ s: Int) -> String {
        let f = DateComponentsFormatter(); f.unitsStyle = .full; f.allowedUnits = s >= 3600 ? [.hour, .minute] : [.minute, .second]
        return f.string(from: TimeInterval(s)) ?? "\(s) seconds"
    }
}

// MARK: snippet views

private let accent = Color(red: 0xC9 / 255, green: 0x50 / 255, blue: 0x28 / 255)

struct SnippetEmpty: View {
    let text: String
    var body: some View { Text(text).font(.headline).foregroundStyle(.secondary).padding() }
}

private struct Cover: View {
    let file: String?
    /// App Group copy first (widgets), then the app's own cover file (works when sideloading dropped the App Group).
    static func load(_ file: String?) -> UIImage? {
        guard let f = file else { return nil }
        if let u = WidgetCovers.url(f), let img = UIImage(contentsOfFile: u.path) { return img }
        return UIImage(contentsOfFile: CoverStore.url(f).path)
    }
    var body: some View {
        Group {
            if let img = Self.load(file) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack { accent.opacity(0.15); Image(systemName: "fork.knife").foregroundStyle(accent) }
            }
        }
        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

struct PickSnippet: View {
    let recipe: RecipeCard
    let why: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Cover(file: WidgetSnapshotBuilder.coverFile(recipe))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title).font(.headline).lineLimit(2)
                    if let m = recipe.timeMinutes { Text("\(m) min").font(.subheadline).foregroundStyle(.secondary) }
                    Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack {
                Button(intent: StartCookModeIntent(recipe: RecipeAppEntity(recipe))) { Label("Cook now", systemImage: "frying.pan") }
                    .buttonStyle(.borderedProminent).tint(accent)
                Button(intent: OpenRecipeIntent(target: RecipeAppEntity(recipe))) { Label("Open", systemImage: "book") }
                    .buttonStyle(.bordered)
            }
        }.padding()
    }
}

struct ShoppingSnippet: View {
    let items: [ShoppingItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty { Text("List is empty").foregroundStyle(.secondary) }
            ForEach(items) { i in
                Button(intent: ToggleShoppingItemIntent(itemID: i.id, done: true)) {
                    Label(i.name, systemImage: "circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).frame(minHeight: 44)
                .accessibilityLabel("Tick \(i.name)")
            }
        }.padding()
    }
}

struct TimerSnippet: View {
    let t: TimerSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.recipeTitle).font(.headline)
            Text("Step \(t.stepIndex + 1) of \(t.stepCount)").font(.caption).foregroundStyle(.secondary)
            Group {
                if let end = t.endDate, end > Date() { Text(timerInterval: Date()...end, countsDown: true) }
                else { Text(String(format: "%d:%02d", t.pausedRemaining / 60, t.pausedRemaining % 60)) }
            }.font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            HStack {
                Button(intent: ToggleTimerIntent(timerID: TimerMath.id(t))) {
                    Label(t.endDate == nil ? "Resume" : "Pause", systemImage: t.endDate == nil ? "play.fill" : "pause.fill")
                }.buttonStyle(.borderedProminent).tint(accent)
                Button(role: .destructive, intent: StopTimerIntent(timerID: TimerMath.id(t))) { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.bordered)
            }
        }.padding()
    }
}

struct QuickSnippet: View {
    let recipes: [RecipeCard]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recipes.isEmpty { Text("No recipes under 30 minutes").foregroundStyle(.secondary) }
            ForEach(recipes) { r in
                Button(intent: OpenRecipeIntent(target: RecipeAppEntity(r))) {
                    HStack(spacing: 10) {
                        Cover(file: WidgetSnapshotBuilder.coverFile(r)).scaleEffect(0.7).frame(width: 46, height: 46)
                        VStack(alignment: .leading) {
                            Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(Durations.plausibleQuickMinutes(r) ?? r.timeMinutes ?? 0) min").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
            }
        }.padding()
    }
}
