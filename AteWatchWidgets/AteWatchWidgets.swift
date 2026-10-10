import WidgetKit
import SwiftUI

/// Smart Stack widget / complication for the current wrist step timer.
struct TimerEntry: TimelineEntry { let date: Date; let timer: WatchStepTimer? }

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { TimerEntry(date: Date(), timer: .start(title: "Pasta", step: 2, seconds: 600)) }
    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) { completion(TimerEntry(date: Date(), timer: WatchTimerStore.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let t = WatchTimerStore.load()
        var entries = [TimerEntry(date: Date(), timer: t)]
        if let end = t?.endDate, end > Date() { entries.append(TimerEntry(date: end, timer: nil)) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry
    var body: some View {
        Group {
            if let t = entry.timer, let end = t.endDate, end > entry.date {
                switch family {
                case .accessoryCircular:
                    ProgressView(timerInterval: Date()...end, countsDown: true) { Image(systemName: "timer") }
                        .progressViewStyle(.circular)
                case .accessoryInline:
                    Text(timerInterval: entry.date...end, countsDown: true)
                default:
                    VStack(alignment: .leading) {
                        Text(t.recipeTitle).font(.headline).lineLimit(1)
                        Text("Step \(t.stepIndex + 1)").font(.caption2)
                        Text(timerInterval: entry.date...end, countsDown: true).font(.title3.bold()).monospacedDigit()
                    }
                }
            } else {
                Label("No timer", systemImage: "timer")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "ate://timer"))
    }
}

@main
struct AteWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ate.watch.timer", provider: TimerProvider()) { TimerWidgetView(entry: $0) }
            .configurationDisplayName("ate timer")
            .description("Your current cook-mode step timer.")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
