import SwiftUI

struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""
    @FocusState private var addFieldFocused: Bool
    @State private var share: ShareItems?
    @State private var editingItem: ShoppingItem?
    @State private var editOwner: String?
    @State private var pendingClear: PendingClear?

    /// Which list clear is awaiting confirmation; one Menu-anchored dialog serves both.
    private enum PendingClear: String, Identifiable {
        case bought, all
        var id: String { rawValue }
        var title: String { self == .bought ? "Clear the bought items?" : "Clear the whole shopping list?" }
    }
    @AppStorage("ate.shopping.byAisle") private var byAisle = true

    var body: some View {
        let pending = store.shopping.filter { !$0.done }
        let done = store.shopping.filter { $0.done }
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(pending.count) to buy" + (done.isEmpty ? "" : " · \(done.count) in the basket"))
                        .font(AteFont.body(14)).foregroundStyle(Theme.mutedForeground)
                    HStack(spacing: 8) {
                        TextField("Add something else…", text: $newItem).font(AteFont.body(15))
                            .padding(.horizontal, 18).frame(height: 48)
                            .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.input))
                            .focused($addFieldFocused)
                            .onSubmit(addManual).accessibilityIdentifier("shoppingAddField")
                        Button(action: addManual) {
                            Image(systemName: "plus").font(.body.weight(.bold)).foregroundStyle(Theme.primaryForeground)
                                .frame(width: 48, height: 48).background(Theme.primary, in: Circle())
                        }.accessibilityLabel("Add item")
                    }
                    if store.shopping.isEmpty {
                        EmptyStateCard(symbol: "basket", title: "Nothing on the list",
                                       message: "Open a recipe and tap “Add to shopping list” — quantities merge automatically.")
                    } else {
                        if byAisle {
                            ForEach(ShoppingLogic.grouped(pending), id: \.aisle) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(g.aisle.rawValue).overline().accessibilityAddTraits(.isHeader)
                                        .accessibilityIdentifier("aisle." + g.aisle.rawValue)
                                    ForEach(g.items) { row($0) }
                                }
                            }
                            if !done.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("In the basket").overline().accessibilityAddTraits(.isHeader)
                                    ForEach(done) { row($0) }
                                }
                            }
                        } else {
                            VStack(spacing: 8) { ForEach(pending + done) { row($0) } }
                        }
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 96)
                .pageWidth()
            }
        }
        .navigationTitle("Shopping list")
        .ateRootNavigationChrome(logoID: "shopping.logo")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { shoppingOptionsMenu } }
        .onAppear { store.bottomAddContext = .shopping }
        .onChange(of: store.requestShoppingAdd) { _, requested in
            guard requested else { return }
            addFieldFocused = true
            store.requestShoppingAdd = false
        }
        .sheet(item: $editingItem) { item in
            ShoppingItemEditor(item: item, editOwner: editOwner) { name, quantity in
                store.editShoppingItem(item.id, name: name, quantity: quantity)
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
            Button { store.toggle(it.id); Haptics.toggle() } label: {
                Image(systemName: it.done ? "checkmark.square.fill" : "square").font(.title2)
                    .foregroundStyle(it.done ? Theme.primary : Theme.mutedForeground).frame(width: 44, height: 44)
            }.accessibilityLabel(it.done ? "Mark \(it.name) as not bought" : "Mark \(it.name) as bought")
            Button { editOwner = store.insightLifecycleAccountID; editingItem = it } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShoppingLogic.label(it)).font(AteFont.body(15)).lineLimit(1)
                        .strikethrough(it.done).foregroundStyle(it.done ? Theme.mutedForeground : Theme.foreground)
                    if let src = (it.sources?.joined(separator: ", ") ?? it.from), !src.isEmpty {
                        Text(src).font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(it.name)")
            .accessibilityIdentifier("shopping.edit.\(it.id)")
            IconButton(symbol: "trash", label: "Remove \(it.name)", tint: Theme.mutedForeground) { store.removeShoppingItemWithUndo(it.id) }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .cardSurface()
        .contextMenu {
            Button { editOwner = store.insightLifecycleAccountID; editingItem = it } label: { Label("Edit item", systemImage: "pencil") }
            Button { store.toggle(it.id) } label: { Label(it.done ? "Mark as not bought" : "Mark as bought", systemImage: "checkmark.square") }
            Button { UIPasteboard.general.string = ShoppingLogic.label(it) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button(role: .destructive) { store.removeShoppingItemWithUndo(it.id) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    /// One top-bar menu for every list-level action: the per-item context menu and its
    /// remove-Undo stay on each row. Export and clear actions stay disabled when they
    /// would have nothing to act on; both clears ask for confirmation first.
    private var shoppingOptionsMenu: some View {
        let hasItems = !store.shopping.isEmpty
        let hasBought = store.shopping.contains { $0.done }
        return Menu {
            Button { addFieldFocused = true } label: { Label("Add item", systemImage: "plus") }
                .accessibilityIdentifier("shopping.menu.add")
            Toggle(isOn: $byAisle) { Label("Group by aisle", systemImage: "square.grid.2x2") }
                .accessibilityIdentifier("toggle.Group by aisle")
            Section("Export") {
                Button { share = ShareItems(items: [ShoppingLogic.exportText(store.shopping)]) } label: {
                    Label("Share List", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = ShoppingLogic.exportText(store.shopping)
                    store.show("Copied as text")
                } label: { Label("Copy Text", systemImage: "doc.on.doc") }
                Button { shareFile("ate-shopping-list.txt", ShoppingLogic.exportText(store.shopping)) } label: {
                    Label("Export as .txt", systemImage: "arrow.down.doc")
                }
                Button { shareFile("ate-shopping-list.csv", ShoppingLogic.exportCSV(store.shopping)) } label: {
                    Label("Export as .csv", systemImage: "arrow.down.doc")
                }
            }
            .disabled(!hasItems)
            Section("Clear") {
                Button(role: .destructive) { pendingClear = .bought } label: { Label("Clear bought items", systemImage: "checkmark") }
                    .disabled(!hasBought)
                Button(role: .destructive) { pendingClear = .all } label: { Label("Clear all items", systemImage: "trash") }
                    .disabled(!hasItems)
            }
        } label: {
            Label("Shopping list options", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("shoppingOptionsMenu")
        // Anchored to the menu that triggers it (popover source on iPad); attached to the
        // always-present Menu, not the transient menu content, so presentation survives dismissal.
        .confirmationDialog(pendingClear?.title ?? "", isPresented: Binding(
            get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            titleVisibility: .visible) {
            if pendingClear == .bought {
                Button("Clear bought items", role: .destructive) { store.clearTicked(); store.show("Bought items cleared") }
            } else {
                Button("Clear all items", role: .destructive) { store.clearShopping(); store.show("List cleared") }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shareFile(_ name: String, _ text: String) {
        if let url = writeTemp(name, Data(text.utf8)) { share = ShareItems(items: [url]) }
    }
}


/// Edit name/quantity only: unit, recipe sources, notes and completion are preserved by
/// `AppStore.editShoppingItem`. Cancel always discards; Save is disabled until the fields
/// are valid, and a failed save explains why instead of dismissing.
private struct ShoppingItemEditor: View {
    let item: ShoppingItem
    let editOwner: String?
    let save: (String, Double) -> Bool
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var saveFailed = false

    private let originalQuantityText: String

    init(item: ShoppingItem, editOwner: String?, save: @escaping (String, Double) -> Bool) {
        self.item = item
        self.editOwner = editOwner
        self.save = save
        let seeded = ShoppingEdit.quantityText(item.quantity)
        originalQuantityText = seeded
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: seeded)
    }

    private var accountChanged: Bool { store.insightLifecycleAccountID != editOwner }
    /// The stored quantity when the field is untouched, the parsed text once it is edited:
    /// a name-only edit is never trapped by an unparseable seeded value.
    private var effectiveQuantity: Double? {
        ShoppingEdit.effectiveQuantity(original: item.quantity, originalText: originalQuantityText, editedText: quantity)
    }
    private var valid: Bool {
        ShoppingEdit.trimmedName(name) != nil && effectiveQuantity != nil && !accountChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name).accessibilityIdentifier("shopping.edit.name")
                TextField("Quantity (optional)", text: $quantity)
                    .keyboardType(.decimalPad).accessibilityIdentifier("shopping.edit.quantity")
                if !item.unit.isEmpty { Text("Unit: \(item.unit)") }
                Text("Leave quantity empty if you don't need an amount. Unit, recipe sources and completion stay unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
                if effectiveQuantity == nil {
                    Text("Enter a quantity of zero or more.").foregroundStyle(.red)
                }
                if accountChanged {
                    Text("Your account changed while you were editing. Cancel and check the current list.")
                        .foregroundStyle(.red)
                } else if saveFailed {
                    Text("This item is no longer on your list. Cancel and check the current list.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = effectiveQuantity else { return }
                        if save(name, value) { dismiss() } else { saveFailed = true }
                    }
                    .disabled(!valid)
                    .accessibilityIdentifier("shopping.edit.save")
                }
            }
        }
    }
}
