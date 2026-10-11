import SwiftUI

struct CookingTrackerView: View {
    @Environment(AppStore.self) private var store
    @State private var history = CookingHistory.shared
    @State private var selectedDate: Date?
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cooking tracker").font(AteFont.display(18))
                Spacer()
                Label("\(history.streak()) day streak", systemImage: "flame.fill")
                    .font(AteFont.body(12, .semibold)).foregroundStyle(Theme.primary)
            }
            Text("Cook mode adds a day automatically. Tap a dot to see what you cooked.")
                .font(AteFont.body(13)).foregroundStyle(Theme.mutedForeground)
            CookingDotGrid(history: history, selectedDate: $selectedDate)
                .accessibilityIdentifier("insights.cookingCalendar")
            HStack {
                Circle().fill(Theme.primary).frame(width: 9, height: 9)
                Text("Cooked").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
                Circle().fill(Theme.input).frame(width: 9, height: 9)
                Text("No cooking recorded").font(AteFont.body(11)).foregroundStyle(Theme.mutedForeground)
            }
        }
        .cardSurface(padding: 16)
        .sheet(item: Binding(get: { selectedDate.map { TrackerDate($0) } }, set: { selectedDate = $0?.date })) { item in
            CookingDaySheet(date: item.date, recipeIDs: history.recipeIDs(on: item.date), recipes: store.recipes)
                .presentationDetents([.medium])
        }
    }
}

private struct TrackerDate: Identifiable { let date: Date; var id: Date { date } }

private struct CookingDotGrid: View {
    let history: CookingHistory
    @Binding var selectedDate: Date?
    private let calendar = Calendar.current
    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<28).compactMap { calendar.date(byAdding: .day, value: -27 + $0, to: today) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date().formatted(.dateTime.month(.wide).year())).font(AteFont.body(12, .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
                ForEach(dates, id: \.self) { date in
                    Button { selectedDate = date } label: {
                        Circle().fill(history.cooked(on: date) ? Theme.primary : Theme.input)
                            .frame(width: 24, height: 24)
                            .overlay(Text(calendar.component(.day, from: date).description).font(.system(size: 9, weight: .semibold)).foregroundStyle(history.cooked(on: date) ? .white : Theme.mutedForeground))
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted) + (history.cooked(on: date) ? ", cooked" : ", no cooking recorded"))
                }
            }
        }
    }
}

private struct CookingDaySheet: View {
    let date: Date
    let recipeIDs: Set<String>
    let recipes: [RecipeCard]
    var body: some View {
        NavigationStack {
            List {
                Section(date.formatted(date: .complete, time: .omitted)) {
                    if recipeIDs.isEmpty { Text("Nothing recorded for this day.").foregroundStyle(.secondary) }
                    ForEach(Array(recipeIDs).sorted(), id: \.self) { id in
                        Label(recipes.first(where: { $0.id == id })?.title ?? "Recipe no longer in your library", systemImage: "fork.knife")
                    }
                }
            }.navigationTitle("Cooked that day").navigationBarTitleDisplayMode(.inline)
        }
    }
}
