import WidgetKit
import SwiftUI
import AppIntents

struct TimersEntry: TimelineEntry {
    let date: Date
    let timers: [TimerSnapshot]
}

struct TimersProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimersEntry {
        TimersEntry(date: Date(), timers: [TimerSnapshot(recipeID: "p", recipeTitle: "Mogodu", stepIndex: 3, stepCount: 6,
                                                        stepText: "Simmer the tripe", total: 1200,
                                                        endDate: Date().addingTimeInterval(760), pausedRemaining: 760)])
    }
    func getSnapshot(in context: Context, completion: @escaping (TimersEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TimersEntry(date: Date(), timers: TimerMath.ordered(TimerSnapshot.load())))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimersEntry>) -> Void) {
        Heartbeat.beat(WidgetKinds.timers)
        let now = Date()
        let all = TimerSnapshot.load()
        var entries = [TimersEntry(date: now, timers: TimerMath.ordered(all, now: now))]
        // One extra entry at each timer end so finished timers drop off without the app.
        let ends = all.compactMap(\.endDate).filter { $0 > now }.sorted()
        for e in ends.prefix(5) { entries.append(TimersEntry(date: e.addingTimeInterval(1), timers: TimerMath.ordered(all, now: e.addingTimeInterval(1)))) }
        completion(Timeline(entries: entries, policy: .after(ends.last?.addingTimeInterval(2) ?? now.addingTimeInterval(1800))))
    }
}

/// Live countdown text that keeps ticking without timeline reloads.
struct TimerText: View {
    let t: TimerSnapshot
    var body: some View {
        if let end = t.endDate, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
        } else {
            Text(WidgetFormat.mmss(t.pausedRemaining)).monospacedDigit()
        }
    }
}

struct ActiveTimersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.timers, provider: TimersProvider()) { e in
            ActiveTimersView(entry: e)
        }
        .configurationDisplayName("Cook timers")
        .description("Your running timers, with pause and stop.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ActiveTimersView: View {
    let entry: TimersEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryCircular: circular.containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular: rectangular.containerBackground(for: .widget) { Color.clear }
        default: home.containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }

    private var next: TimerSnapshot? { entry.timers.first }

    @ViewBuilder private var circular: some View {
        if let t = next {
            ZStack {
                if let end = t.endDate, end > Date() {
                    ProgressView(timerInterval: end.addingTimeInterval(-Double(t.total))...end, countsDown: true) { EmptyView() } currentValueLabel: {
                        Image(systemName: "timer")
                    }
                    .progressViewStyle(.circular)
                } else {
                    Gauge(value: Double(t.pausedRemaining), in: 0...Double(max(1, t.total))) { Image(systemName: "pause.fill") }
                        .gaugeStyle(.accessoryCircularCapacity)
                }
            }
            .widgetURL(WidgetLinks.timers)
            .accessibilityLabel("Next timer, \(WidgetFormat.mmss(TimerMath.remaining(t))) left")
        } else {
            Image(systemName: "timer").font(.title2).widgetURL(WidgetLinks.timers).accessibilityLabel("No timers")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let t = next {
            VStack(alignment: .leading, spacing: 1) {
                Text(t.recipeID == TimerMath.quickRecipeID ? "Kitchen timer" : "Step \(t.stepIndex + 1) · \(shortTitle(t))")
                    .font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    TimerText(t: t).font(.title3.weight(.semibold))
                    Text(t.endDate == nil ? "paused" : "left").font(.caption)
                }
                Text(t.recipeTitle).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(t.recipeID == TimerMath.quickRecipeID ? WidgetLinks.timers : WidgetLinks.cook(t.recipeID))
            .accessibilityLabel(WidgetFormat.stepLine(t))
        } else {
            Label("No timers running", systemImage: "timer").font(.caption)
        }
    }

    private func shortTitle(_ t: TimerSnapshot) -> String {
        let s = t.stepText.split(separator: ".").first.map(String.init) ?? t.stepText
        return s.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder private var home: some View {
        if entry.timers.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "timer").font(.title2).foregroundStyle(WTheme.primary)
                Text("No timers running").font(.caption).foregroundStyle(.secondary)
                Button(intent: KitchenTimerIntent()) {
                    Label("5 min", systemImage: "play.fill").font(.caption.weight(.semibold))
                }
                .tint(WTheme.primary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.timers.prefix(family == .systemSmall ? 1 : 2).enumerated()), id: \.offset) { _, t in row(t) }
                if entry.timers.count > (family == .systemSmall ? 1 : 2) {
                    Text("+\(entry.timers.count - (family == .systemSmall ? 1 : 2)) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(WidgetLinks.timers)
        }
    }

    private func row(_ t: TimerSnapshot) -> some View {
        let id = TimerMath.id(t)
        return VStack(alignment: .leading, spacing: 4) {
            Text(t.recipeID == TimerMath.quickRecipeID ? "Kitchen timer" : "\(t.recipeTitle) · Step \(t.stepIndex + 1)")
                .font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.secondary)
            HStack {
                TimerText(t: t).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(WTheme.primary)
                Spacer(minLength: 4)
                Button(intent: ToggleTimerIntent(timerID: id)) {
                    Image(systemName: t.endDate == nil ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(t.endDate == nil ? "Resume" : "Pause")
                Button(intent: StopTimerIntent(timerID: id)) { Image(systemName: "stop.fill") }
                    .accessibilityLabel("Stop")
            }
            .tint(WTheme.primary)
        }
    }
}

// MARK: Control Center (iOS 18)

enum KitchenTimerState: String {
    case idle, running, paused
    var title: String { self == .running ? "Pause timer" : self == .paused ? "Resume timer" : "Kitchen timer" }
    var symbol: String { self == .running ? "pause.fill" : self == .paused ? "play.fill" : "timer" }
}

struct KitchenTimerValueProvider: ControlValueProvider {
    var previewValue: KitchenTimerState { .idle }
    func currentValue() async throws -> KitchenTimerState {
        let live = TimerMath.ordered(TimerSnapshot.load())
        if live.contains(where: { $0.endDate != nil }) { return .running }
        return live.isEmpty ? .idle : .paused
    }
}

struct KitchenTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.kitchenControl, provider: KitchenTimerValueProvider()) { state in
            ControlWidgetButton(action: KitchenTimerIntent()) {
                Label(state.title, systemImage: state.symbol)
            }
        }
        .displayName("Kitchen timer")
        .description("Start a 5-minute timer, or pause and resume the running one.")
    }
}

struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.quickAddControl) {
            ControlWidgetButton(action: QuickAddIntent(mode: .link)) {
                Label("Add recipe", systemImage: "plus.circle")
            }
        }
        .displayName("Add to ate")
        .description("Open ate on Add recipe.")
    }
}
