import WidgetKit
import SwiftUI
import AppIntents
import ImageIO

// MARK: palette

enum WTheme {
    static let primary = Color(red: 0xC9 / 255, green: 0x50 / 255, blue: 0x28 / 255)
    static let cream = Color(red: 0xF5 / 255, green: 0xE2 / 255, blue: 0xC0 / 255)
    static let brown = Color(red: 0x51 / 255, green: 0x2E / 255, blue: 0x1A / 255)
}

/// Placeholder shown when the extension can't read the App Group (common on free-Apple-ID sideloads).
struct NoDataView: View {
    var text = "Open ate to set up this widget"
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife").font(.title3).foregroundStyle(WTheme.primary)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "ate://open"))
    }
}

enum Heartbeat {
    static func beat(_ kind: String) {
        guard SharedContainer.isAvailable else { return }
        var m = (SharedContainer.defaults.dictionary(forKey: WidgetKinds.heartbeatKey) as? [String: Double]) ?? [:]
        m[kind] = Date().timeIntervalSince1970
        SharedContainer.defaults.set(m, forKey: WidgetKinds.heartbeatKey)
    }
}

/// Downsampled cover from the App Group (keeps the extension well under its memory limit).
enum CoverThumb {
    static func image(_ file: String?, max: CGFloat = 360) -> UIImage? {
        guard let f = file, let u = WidgetCovers.url(f), let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct CoverView: View {
    let file: String?
    let title: String
    var body: some View {
        if let img = CoverThumb.image(file) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [WTheme.cream, WTheme.primary.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "fork.knife").font(.title2).foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel(title)
        }
    }
}

// MARK: snapshot-backed provider

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let groupAvailable: Bool
}

struct SnapshotProvider: TimelineProvider {
    let kind: String
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample, groupAvailable: true) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        Heartbeat.beat(kind)
        // The app reloads these whenever recipes, favourites, the list or Health change; hourly refresh as a safety net.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }
    private func entry() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load(), groupAvailable: SharedContainer.isAvailable)
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.favourites = [
            .init(id: "1", title: "Mogodu", minutes: 180, favorite: true, cover: nil, stepCount: 6),
            .init(id: "2", title: "Chakalaka", minutes: 35, favorite: true, cover: nil, stepCount: 5),
            .init(id: "3", title: "Pap", minutes: 25, favorite: true, cover: nil, stepCount: 3),
            .init(id: "4", title: "Malva pudding", minutes: 60, favorite: true, cover: nil, stepCount: 7),
        ]
        s.shopping = [.init(id: "a", name: "Milk", done: false), .init(id: "b", name: "Onions", done: false), .init(id: "c", name: "Maize meal", done: false)]
        s.pick = .init(recipeID: "2", title: "Chakalaka", why: "Lighter and comforting", minutes: 35, cover: nil,
                       healthTitle: "Low-energy day", healthSymbol: "moon.zzz")
        s.recipeCount = 12
        return s
    }
}

// MARK: Tonight's pick

struct TonightsPickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pick, provider: SnapshotProvider(kind: WidgetKinds.pick)) { e in
            TonightsPickView(entry: e).containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Tonight's pick")
        .description("One recipe from your library that fits your day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TonightsPickView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let p = entry.snapshot?.pick {
            let content = HStack(spacing: 12) {
                if family == .systemMedium {
                    CoverView(file: p.cover, title: p.title).frame(width: 110).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(p.healthTitle ?? "Tonight's pick", systemImage: p.healthSymbol ?? "sparkles")
                        .font(.caption2.weight(.semibold)).foregroundStyle(WTheme.primary).lineLimit(1)
                    Text(p.title).font(.headline).lineLimit(2)
                    Text(p.why).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    HStack {
                        if let m = p.minutes { Label("\(m) min", systemImage: "clock").font(.caption2).foregroundStyle(.secondary) }
                        if family == .systemMedium {
                            Spacer()
                            Link(destination: WidgetLinks.cook(p.recipeID)) {
                                Label("Cook", systemImage: "frying.pan").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(WTheme.primary, in: Capsule()).foregroundStyle(.white)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            content.widgetURL(WidgetLinks.recipe(p.recipeID))
        } else if entry.groupAvailable && entry.snapshot != nil {
            NoDataView(text: "Save a recipe to get tonight's pick")
        } else {
            NoDataView()
        }
    }
}

// MARK: Shopping list

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.shopping, provider: SnapshotProvider(kind: WidgetKinds.shopping)) { e in
            ShoppingWidgetView(entry: e).containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Shopping list")
        .description("Tick items off right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShoppingWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    var limit: Int { family == .systemLarge ? 8 : family == .systemMedium ? 4 : 3 }
    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Shopping", systemImage: "basket").font(.caption.weight(.semibold)).foregroundStyle(WTheme.primary)
                    Spacer()
                    Text("\(s.openItems.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if s.openItems.isEmpty {
                    Spacer()
                    Text("All done 🎉").font(.subheadline).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(s.openItems.prefix(limit)) { it in
                        Button(intent: ToggleShoppingItemIntent(itemID: it.id, done: true)) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle").foregroundStyle(WTheme.primary)
                                Text(it.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tick off \(it.name)")
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(WidgetLinks.shopping)
        } else { NoDataView() }
    }
}

/// Lock Screen inline: "🧺 Milk · 3 more".
struct ShoppingInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.shoppingInline, provider: SnapshotProvider(kind: WidgetKinds.shoppingInline)) { e in
            Group {
                if let s = e.snapshot, let n = s.nextItem {
                    let more = s.openItems.count - 1
                    Label(more > 0 ? "\(n.name) · \(more) more" : n.name, systemImage: "basket")
                } else {
                    Label(e.snapshot == nil ? "Open ate" : "List done", systemImage: "basket")
                }
            }
            .widgetURL(WidgetLinks.shopping)
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next on your list")
        .description("The next unticked shopping item, by the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: Quick add

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.quickAdd, provider: SnapshotProvider(kind: WidgetKinds.quickAdd)) { _ in
            QuickAddView().containerBackground(for: .widget) { WTheme.cream }
        }
        .configurationDisplayName("Quick add")
        .description("Add a recipe from a link, a photo or a prompt.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickAddView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Add recipe", systemImage: "plus.circle.fill").font(.caption.weight(.bold)).foregroundStyle(WTheme.primary)
            ForEach(QuickAddMode.allCases, id: \.self) { m in
                Button(intent: QuickAddIntent(mode: m)) {
                    HStack {
                        Image(systemName: m == .link ? "link" : m == .photo ? "photo" : "pencil.line").frame(width: 18)
                        Text(m == .link ? "Link" : m == .photo ? "Photo" : "Prompt").font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(WTheme.brown)
        .widgetURL(WidgetLinks.add(.link))
    }
}

// MARK: Favourites shelf

struct FavouritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.favourites, provider: SnapshotProvider(kind: WidgetKinds.favourites)) { e in
            FavouritesView(entry: e).containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Favourites")
        .description("Your favourite recipes, one tap away.")
        .supportedFamilies([.systemMedium])
    }
}

struct FavouritesView: View {
    let entry: SnapshotEntry
    var body: some View {
        if let s = entry.snapshot {
            if s.favourites.isEmpty {
                NoDataView(text: "Star a recipe to see it here")
            } else {
                HStack(spacing: 8) {
                    ForEach(s.favourites.prefix(WidgetSnapshot.maxFavourites)) { r in
                        Link(destination: WidgetLinks.recipe(r.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverView(file: r.cover, title: r.title)
                                    .frame(maxWidth: .infinity).frame(height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(r.title).font(.caption2.weight(.semibold)).lineLimit(2)
                            }
                        }
                    }
                }
            }
        } else { NoDataView() }
    }
}
