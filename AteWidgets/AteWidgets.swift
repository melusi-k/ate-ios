import WidgetKit
import SwiftUI
import ActivityKit

@main
struct AteWidgetsBundle: WidgetBundle {
    init() { SharedWriterBoundary.installExtensionStartup() }
    var body: some Widget {
        CookTimerLiveActivity()
        ActiveTimersWidget()
        TonightsPickWidget()
        ShoppingWidget()
        ShoppingInlineWidget()
        QuickAddWidget()
        FavouritesWidget()
        CookingWidget()
        KitchenTimerControl()
        QuickAddControl()
    }
}

private let terracotta = Color(red: 0xC9 / 255, green: 0x50 / 255, blue: 0x28 / 255)
private let warm = Color(red: 0xF5 / 255, green: 0xE2 / 255, blue: 0xC0 / 255)
private let warmFg = Color(red: 0x51 / 255, green: 0x2E / 255, blue: 0x1A / 255)

private func mmss(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

struct Countdown: View {
    let state: CookTimerAttributes.ContentState
    var body: some View {
        if state.finished {
            Text("Done")
        } else if let end = state.endDate, end > state.startDate {
            Text(timerInterval: state.startDate...end, countsDown: true).monospacedDigit()
        } else {
            Text(mmss(state.remaining)).monospacedDigit()
        }
    }
}

struct CookTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookTimerAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 14) {
                Image(systemName: context.state.endDate == nil ? "pause.circle.fill" : "timer")
                    .font(.system(size: 30)).foregroundStyle(terracotta)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.recipeTitle).font(.headline).lineLimit(1)
                    Text("Step \(context.state.stepIndex + 1) of \(context.state.stepCount)" + (context.state.endDate == nil ? " · paused" : ""))
                        .font(.caption).opacity(0.8)
                    Text(context.state.stepText).font(.caption2).lineLimit(1).opacity(0.7)
                }
                Spacer()
                Countdown(state: context.state).font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .foregroundStyle(warmFg)
            .padding(16)
            .activityBackgroundTint(warm)
            .activitySystemActionForegroundColor(warmFg)
            .widgetURL(URL(string: "ate://cook/\(context.attributes.recipeID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Step \(context.state.stepIndex + 1)", systemImage: "timer").foregroundStyle(terracotta).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 76, alignment: .trailing)
                        .layoutPriority(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Full-width text no longer competes with the countdown's region.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.recipeTitle).font(.headline).lineLimit(2)
                        Text(context.state.stepText).font(.caption).lineLimit(2).opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(terracotta)
            } compactTrailing: {
                Countdown(state: context.state).font(.caption.bold())
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.endDate == nil ? "pause.fill" : "timer").foregroundStyle(terracotta)
            }
            .widgetURL(URL(string: "ate://cook/\(context.attributes.recipeID)"))
            .keylineTint(terracotta)
        }
    }
}
