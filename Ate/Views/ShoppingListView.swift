import SwiftUI

struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""
    @FocusState private var addFieldFocused: Bool
    @State private var share: ShareItems?
    @State private var editingItem: ShoppingItem?
    @State private var editOwner: String?
    @State private var confirmClearAll = false
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
                        Toggle(isOn: $byAisle) { Label("Group by aisle", systemImage: "square.grid.2x2") }
                            .font(AteFont.body(15, .medium)).tint(Theme.primary).accessibilityIdentifier("toggle.Group by aisle")
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
                        exportCard(done: !done.isEmpty)
                    }
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 96)
                .pageWidth()
            }
        }
        .navigationTitle("Shopping list")
        .ateRootNavigationChrome(logoID: "shopping.logo")
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
                Button("Clear all") { confirmClearAll = true }
                    .buttonStyle(.ate(.destructiveGhost, height: 40))
                    // Anchored to the button that triggered it (popover source on iPad).
                    .confirmationDialog("Clear the whole shopping list?", isPresented: $confirmClearAll, titleVisibility: .visible) {
                        Button("Clear all items", role: .destructive) { store.clearShopping(); store.show("List cleared") }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
        .cardSurface(padding: 20)
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
