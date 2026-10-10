import SwiftUI
import UIKit
import LinkPresentation

struct TagBadge: View {
    let text: String
    var outline = false
    var body: some View {
        Text(text).font(AteFont.body(12, .medium))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(outline ? Theme.warmForeground : Theme.secondaryForeground)
            .background(outline ? Color.clear : Theme.secondary, in: Capsule())
            .overlay { if outline { Capsule().stroke(Theme.warmForeground.opacity(0.3)) } }
    }
}

struct RecipeCardView: View {
    let recipe: RecipeCard
    var factor: Double = 1
    var units: UnitSystem = .metric

    var body: some View {
        let r = RecipeLogic.scaled(recipe, factor: factor)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(r.title).font(AteFont.display(24)).foregroundStyle(Theme.warmForeground)
                if let d = r.description, !d.isEmpty {
                    Text(d).font(AteFont.body(14)).foregroundStyle(Theme.warmForeground.opacity(0.8))
                }
                HStack(spacing: 14) {
                    if let m = r.timeMinutes, m > 0 { Label("\(m) min", systemImage: "clock") }
                    Label("\(r.servings) servings", systemImage: "person.2")
                }
                .font(AteFont.body(13, .medium)).foregroundStyle(Theme.warmForeground)
                if !r.tags.isEmpty {
                    FlowRow(r.tags) { TagBadge(text: $0, outline: true) }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warm)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredients").overline()
                    ForEach(Array(r.ingredients.enumerated()), id: \.offset) { _, ing in
                        let (q, u) = Units.convert(quantity: ing.quantity, unit: ing.unit, to: units)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Units.formatAmount(q, u)).font(AteFont.body(15, .medium)).monospacedDigit()
                                .frame(width: 96, alignment: .leading)
                            (Text(ing.name) + Text(ing.notes.map { $0.isEmpty ? "" : " — \($0)" } ?? "").foregroundColor(Theme.mutedForeground))
                                .font(AteFont.body(15))
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Steps").overline()
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { idx, s in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(idx + 1)").font(AteFont.body(12, .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(Theme.primary, in: Circle())
                            (Text(Units.convertTemperatures(in: s.instruction, to: units))
                             + Text(Durations.spans(in: s.instruction).isEmpty ? (s.timeSeconds.map { $0 > 0 ? " (\(Int((Double($0) / 60).rounded())) min)" : "" } ?? "") : "").foregroundColor(Theme.mutedForeground))
                                .font(AteFont.body(15))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
        }
        .foregroundStyle(Theme.foreground)
        .cardSurface()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Simple wrapping row for tags.
struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    init(_ items: [String], @ViewBuilder content: @escaping (String) -> Content) { self.items = items; self.content = content }
    var body: some View {
        WrapLayout(spacing: 6) { ForEach(items, id: \.self) { content($0) } }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

struct RecipeThumb: View {
    let recipe: RecipeCard
    var width: CGFloat? = 56
    var height: CGFloat = 56
    var emojiSize: CGFloat = 26
    var cornerRadius: CGFloat = 16
    var body: some View {
        RecipeCover(recipe: recipe, symbolSize: emojiSize)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct RecipeRowView: View {
    let recipe: RecipeCard
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RecipeThumb(recipe: recipe)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(AteFont.body(18, .semibold)).lineLimit(1)
                if let d = recipe.description, !d.isEmpty {
                    Text(d).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let m = recipe.timeMinutes, m > 0 { Label("\(m) min", systemImage: "clock") }
                    Label("\(recipe.servings)", systemImage: "person.2")
                    ForEach(recipe.tags.prefix(2), id: \.self) { TagBadge(text: $0) }
                }
                .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.foreground)
        .cardSurface(padding: 16)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct AteField: ViewModifier {
    func body(content: Content) -> some View {
        content.font(AteFont.body(15)).padding(.horizontal, 12).frame(minHeight: 40)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.input))
    }
}
extension View { func ateField() -> some View { modifier(AteField()) } }

struct RecipeEditor: View {
    @Binding var recipe: RecipeCard

    private var tagsText: Binding<String> {
        Binding(get: { recipe.tags.joined(separator: ", ") },
                set: { recipe.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })
    }
    private var descText: Binding<String> {
        Binding(get: { recipe.description ?? "" }, set: { recipe.description = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Title") { TextField("Title", text: $recipe.title).ateField().accessibilityIdentifier("editorTitle") }
            labeled("Description") { TextField("Description", text: descText, axis: .vertical).lineLimit(2...4).ateField() }
            labeled("Cuisine") {
                TextField("e.g. Italian", text: Binding(get: { recipe.cuisine ?? "" },
                                                       set: { recipe.cuisine = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }))
                    .ateField().accessibilityIdentifier("editorCuisine")
            }
            HStack(spacing: 12) {
                labeled("Servings") {
                    TextField("2", value: $recipe.servings, format: .number).keyboardType(.numberPad).ateField()
                }
                labeled("Total minutes") {
                    TextField("30", value: optInt($recipe.timeMinutes), format: .number).keyboardType(.numberPad).ateField()
                }
            }
            labeled("Tags") { TextField("comma separated", text: tagsText).ateField() }

            HStack {
                Text("Ingredients").overline()
                Spacer()
                Button { recipe.ingredients.append(Ingredient(name: "", quantity: 0, unit: "", notes: nil)) } label: {
                    Label("Add", systemImage: "plus")
                }.buttonStyle(.ate(.secondary, height: 32))
            }
            ForEach(recipe.ingredients.indices, id: \.self) { i in
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("qty", value: ing(i, \.quantity, 0), format: .number)
                            .keyboardType(.decimalPad).frame(width: 80).ateField()
                        TextField("unit", text: ing(i, \.unit, "")).frame(width: 80).ateField()
                        TextField("ingredient", text: ing(i, \.name, "")).ateField()
                        IconButton(symbol: "trash", label: "Remove ingredient", tint: Theme.mutedForeground) {
                            if recipe.ingredients.indices.contains(i) { recipe.ingredients.remove(at: i) }
                        }
                    }
                    TextField("notes (e.g. finely chopped)", text: Binding(
                        get: { recipe.ingredients.indices.contains(i) ? (recipe.ingredients[i].notes ?? "") : "" },
                        set: { if recipe.ingredients.indices.contains(i) { recipe.ingredients[i].notes = $0.isEmpty ? nil : $0 } }))
                        .ateField()
                }
            }

            HStack {
                Text("Steps").overline()
                Spacer()
                Button {
                    recipe.steps.append(Step(order: recipe.steps.count + 1, instruction: "", timeSeconds: nil))
                } label: { Label("Add", systemImage: "plus") }.buttonStyle(.ate(.secondary, height: 32))
            }
            ForEach(recipe.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 6) {
                    TextField("Instruction", text: stp(i, \.instruction, ""), axis: .vertical).lineLimit(2...6).ateField()
                    TextField("sec", value: optInt(stp(i, \.timeSeconds, nil)), format: .number)
                        .keyboardType(.numberPad).frame(width: 96).ateField()
                    IconButton(symbol: "trash", label: "Remove step", tint: Theme.mutedForeground) {
                        if recipe.steps.indices.contains(i) { recipe.steps.remove(at: i) }
                        for j in recipe.steps.indices { recipe.steps[j].order = j + 1 }
                    }
                }
            }
        }
        .foregroundStyle(Theme.foreground)
    }

    /// Bounds-checked bindings: rows can be deleted while SwiftUI still renders the old index.
    private func ing<T>(_ i: Int, _ kp: WritableKeyPath<Ingredient, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { recipe.ingredients.indices.contains(i) ? recipe.ingredients[i][keyPath: kp] : fallback },
                set: { if recipe.ingredients.indices.contains(i) { recipe.ingredients[i][keyPath: kp] = $0 } })
    }
    private func stp<T>(_ i: Int, _ kp: WritableKeyPath<Step, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { recipe.steps.indices.contains(i) ? recipe.steps[i][keyPath: kp] : fallback },
                set: { if recipe.steps.indices.contains(i) { recipe.steps[i][keyPath: kp] = $0 } })
    }

    private func optInt(_ b: Binding<Int?>) -> Binding<Int> {
        Binding(get: { b.wrappedValue ?? 0 }, set: { b.wrappedValue = $0 > 0 ? $0 : nil })
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AteFont.body(13, .medium)).foregroundStyle(Theme.mutedForeground)
            c()
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(AppStore.self) private var store: AppStore?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Theme.destructive : Theme.accent)
            Text(toast.message).font(AteFont.body(14, .medium)).foregroundStyle(Theme.foreground)
            if let a = toast.actionTitle {
                Button(a) { store?.runToastAction() }
                    .font(AteFont.body(14, .bold)).foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("toastAction")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .padding(.horizontal, 16)
    }
}

struct EmptyStateCard: View {
    var symbol: String? = nil
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.primary) }
            Text(title).font(AteFont.display(20))
            Text(message).font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.vertical, 56).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

struct BackBar<Trailing: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            Button(action: action) { Label(title, systemImage: "chevron.left") }.accessibilityIdentifier("backBar")
                .buttonStyle(.ate(.ghost, height: 44))
            Spacer()
            trailing()
        }
    }
}
extension BackBar where Trailing == EmptyView {
    init(title: String, action: @escaping () -> Void) { self.init(title: title, action: action, trailing: { EmptyView() }) }
}

/// UIActivityViewController wrapper.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItems: Identifiable { let id = UUID(); let items: [Any] }

/// Shares exactly one URL with rich link metadata so Messages shows a preview card, not a raw link.
final class LinkShareSource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let image: UIImage?
    init(url: URL, title: String, image: UIImage?) { self.url = url; self.title = title; self.image = image }
    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { url }
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ c: UIActivityViewController, subjectForActivityType t: UIActivity.ActivityType?) -> String { title }
    func activityViewControllerLinkMetadata(_ c: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.originalURL = url
        m.url = url
        m.title = title
        if let image {
            m.iconProvider = NSItemProvider(object: image)
            m.imageProvider = NSItemProvider(object: image)
        }
        return m
    }
}

@MainActor func thumbnailImage(for recipe: RecipeCard) -> UIImage? {
    let r = ImageRenderer(content: RecipeThumb(recipe: recipe).frame(width: 56, height: 56))
    r.scale = 6
    return r.uiImage
}

func writeTemp(_ name: String, _ data: Data) -> URL? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    do { try data.write(to: url, options: .atomic); return url } catch { return nil }
}

/// Inline failure with a Retry button (AI import, shared recipe load, sync).
struct ErrorRetryCard: View {
    let message: String
    var retryID = "retryButton"
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.destructive).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(AteFont.body(14)).fixedSize(horizontal: false, vertical: true)
                Button { retry() } label: { Label(L10n.retry, systemImage: "arrow.clockwise") }
                    .buttonStyle(.ate(.secondary, height: 36)).accessibilityIdentifier(retryID)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.destructive.opacity(0.35)))
        .accessibilityElement(children: .contain)
    }
}

/// Shown at the top of the app while there is no network.
struct OfflineBanner: View {
    var body: some View {
        Label(L10n.offlineBanner, systemImage: "wifi.slash")
            .font(AteFont.body(13, .medium)).foregroundStyle(Theme.warmForeground)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.warm, in: Capsule())
            .accessibilityIdentifier("offlineBanner")
    }
}

/// Small provenance pill ("Made with Apple Intelligence", "Imported from page data", "Demo").
struct SourceBadge: View {
    let source: RecipeSource
    var body: some View {
        if let text = source.badge {
            Label(text, systemImage: source.symbol)
                .font(AteFont.body(12, .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.secondary, in: Capsule())
                .foregroundStyle(Theme.secondaryForeground)
                .accessibilityIdentifier("sourceBadge")
                .accessibilityLabel(text)
        }
    }
}
