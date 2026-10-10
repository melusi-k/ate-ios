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
                             + Text(s.timeSeconds.map { $0 > 0 ? " (\(Int((Double($0) / 60).rounded())) min)" : "" } ?? "").foregroundColor(Theme.mutedForeground))
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
    var body: some View {
        let seed = (recipe.title + recipe.tags.joined()).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let emojis = ["🍲", "🥗", "🍝", "🍛", "🥘", "🍜", "🥙", "🍳", "🍰", "🥞", "🌮", "🍣"]
        let hue = Double(seed % 360) / 360
        ZStack {
            if let s = recipe.imageURL, s.hasPrefix("http"), let url = URL(string: s) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.warm }
            } else {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.95),
                                        Color(hue: hue + 0.08, saturation: 0.55, brightness: 0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(emojis[seed % emojis.count]).font(.system(size: 26))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        TextField("qty", value: $recipe.ingredients[i].quantity, format: .number)
                            .keyboardType(.decimalPad).frame(width: 80).ateField()
                        TextField("unit", text: $recipe.ingredients[i].unit).frame(width: 80).ateField()
                        TextField("ingredient", text: $recipe.ingredients[i].name).ateField()
                        IconButton(symbol: "trash", label: "Remove ingredient", tint: Theme.mutedForeground) {
                            recipe.ingredients.remove(at: i)
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
                    TextField("Instruction", text: $recipe.steps[i].instruction, axis: .vertical).lineLimit(2...6).ateField()
                    TextField("sec", value: optInt($recipe.steps[i].timeSeconds), format: .number)
                        .keyboardType(.numberPad).frame(width: 96).ateField()
                    IconButton(symbol: "trash", label: "Remove step", tint: Theme.mutedForeground) {
                        recipe.steps.remove(at: i)
                        for j in recipe.steps.indices { recipe.steps[j].order = j + 1 }
                    }
                }
            }
        }
        .foregroundStyle(Theme.foreground)
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Theme.destructive : Theme.accent)
            Text(toast.message).font(AteFont.body(14, .medium)).foregroundStyle(Theme.foreground)
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
            Button(action: action) { Label(title, systemImage: "chevron.left") }
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
