import SwiftUI

struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""
    @State private var share: ShareItems?

    var body: some View {
        let pending = store.shopping.filter { !$0.done }
        let done = store.shopping.filter { $0.done }
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BackBar(title: "Library") { store.path.removeAll() }
                    Text("Shopping list").font(AteFont.display(30))
                    Text("\(pending.count) to buy" + (done.isEmpty ? "" : " · \(done.count) in the basket"))
                        .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                    HStack(spacing: 8) {
                        TextField("Add something else…", text: $newItem).font(AteFont.body(15))
                            .padding(.horizontal, 18).frame(height: 48)
                            .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.input))
                            .onSubmit(addManual).accessibilityIdentifier("shoppingAddField")
                        Button(action: addManual) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.primaryForeground)
                                .frame(width: 48, height: 48).background(Theme.primary, in: Circle())
                        }.accessibilityLabel("Add item")
                    }
                    if store.shopping.isEmpty {
                        EmptyStateCard(symbol: "basket", title: "Nothing on the list",
                                       message: "Open a recipe and tap “Add to shopping list” — quantities merge automatically.")
                    } else {
                        VStack(spacing: 8) { ForEach(pending + done) { row($0) } }
                        exportCard(done: !done.isEmpty)
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                .pageWidth()
            }
        }
        .sheet(item: $share) { ActivityView(items: $0.items).presentationDetents([.medium, .large]) }
    }

    private func addManual() {
        store.addManual(newItem)
        newItem = ""
    }

    private func row(_ it: ShoppingItem) -> some View {
        HStack(spacing: 12) {
            Button { store.toggle(it.id) } label: {
                Image(systemName: it.done ? "checkmark.square.fill" : "square").font(.system(size: 22))
                    .foregroundStyle(it.done ? Theme.primary : Theme.mutedForeground).frame(width: 44, height: 44)
            }.accessibilityLabel(it.done ? "Mark \(it.name) as not bought" : "Mark \(it.name) as bought")
            VStack(alignment: .leading, spacing: 2) {
                Text(ShoppingLogic.label(it)).font(AteFont.body(15)).lineLimit(1)
                    .strikethrough(it.done).foregroundStyle(it.done ? Theme.mutedForeground : Theme.foreground)
                if let src = (it.sources?.joined(separator: ", ") ?? it.from), !src.isEmpty {
                    Text(src).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                }
            }
            Spacer()
            IconButton(symbol: "trash", label: "Remove \(it.name)", tint: Theme.mutedForeground) { store.removeItem(it.id) }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .cardSurface()
    }

    private func exportCard(done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export").font(AteFont.display(18))
            WrapLayout(spacing: 8) {
                Button { share = ShareItems(items: [ShoppingLogic.exportText(store.shopping)]) } label: {
                    Label("Share / copy", systemImage: "square.and.arrow.up")
                }.buttonStyle(.ate(.primary, height: 40))
                Button {
                    UIPasteboard.general.string = ShoppingLogic.exportText(store.shopping)
                    store.show("Copied as text")
                } label: { Label("Copy text", systemImage: "doc.on.doc") }.buttonStyle(.ate(.secondary, height: 40))
                Button { shareFile("ate-shopping-list.txt", ShoppingLogic.exportText(store.shopping)) } label: {
                    Label(".txt", systemImage: "arrow.down.doc")
                }.buttonStyle(.ate(.secondary, height: 40))
                Button { shareFile("ate-shopping-list.csv", ShoppingLogic.exportCSV(store.shopping)) } label: {
                    Label(".csv", systemImage: "arrow.down.doc")
                }.buttonStyle(.ate(.secondary, height: 40))
            }
            HStack {
                Button { store.clearTicked() } label: { Label("Clear ticked", systemImage: "checkmark") }
                    .buttonStyle(.ate(.ghost, height: 40)).disabled(!done)
                Button("Clear all") { store.clearShopping(); store.show("List cleared") }
                    .buttonStyle(.ate(.destructiveGhost, height: 40))
            }
        }
        .cardSurface(padding: 20)
    }

    private func shareFile(_ name: String, _ text: String) {
        if let url = writeTemp(name, Data(text.utf8)) { share = ShareItems(items: [url]) }
    }
}
