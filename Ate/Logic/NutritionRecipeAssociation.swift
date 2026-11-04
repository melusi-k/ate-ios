import Foundation

/// A durable link between a canonical diary entry and a recipe (#179 recipe association).
/// The recipe name is a snapshot taken when the link is made: the diary keeps showing what the
/// link pointed at even if the recipe is renamed or deleted later. A link never carries
/// nutrients - an entry's values stay exactly what the person logged, and no macro is ever
/// derived from a recipe (the verified catalogue is empty and unverified macros are never
/// presented as reliable).
struct NutritionRecipeAssociation: Codable, Equatable {
    /// The canonical diary entry's stable identity (its UUID string).
    var entryID: String
    /// The recipe's stable identity (`RecipeCard.id`).
    var recipeID: String
    /// The recipe's title at link time.
    var recipeName: String
    var linkedAt: Date
}

enum NutritionRecipeAssociationLoadState: Equatable {
    case absent
    case corrupt
    case loaded([NutritionRecipeAssociation])
}

enum NutritionRecipeAssociationError: Error {
    /// The store holds undecodable bytes. Saving is refused while they occupy the store:
    /// overwriting them would destroy the only copy.
    case storeUnreadable
    /// No link store was wired into the controller (composition has not provided one). This
    /// says nothing about saved links - the feature is simply unavailable in this configuration.
    case storeNotWired
}

extension NutritionRecipeAssociationError: LocalizedError {
    /// Human-readable causes; the raw `localizedDescription` of a bare enum case
    /// ("Ate.NutritionRecipeAssociationError error 0.") must never reach the UI.
    var errorDescription: String? {
        switch self {
        case .storeUnreadable:
            return "The saved recipe links couldn't be read. They look damaged and haven't been changed or overwritten; your diary entries are unaffected."
        case .storeNotWired:
            return "Recipe linking isn't available in this configuration. The entry itself is unaffected."
        }
    }
}

/// Sidecar store for recipe links (#179). Deliberately separate from `JournalMealPayload`: the
/// unified journal schema belongs to the pinned #245 foundation, so links live in their own
/// durable store keyed by entry identity. This store never touches the legacy
/// ate.nutritionDiary.v1 payload, and a missing or unreadable link never blocks diary reads or
/// writes - the entry simply shows no linked recipe, and the controller says so honestly.
///
/// KNOWN GAP, recorded before any activation: these links are NOT part of the export archive
/// (archive v1 covers recipes, shopping, diary entries and goals only). The canonical archive
/// contract must be extended to include recipe links - with identity-preserving import - and a
/// migration path decided, before this store can become production truth. Until then this
/// remains an unactivated candidate sidecar, not a permanent parallel record.
struct NutritionRecipeAssociationStore {
    let defaults: UserDefaults
    static let storageKey = "ate.nutritionRecipeAssociations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Distinguishes an absent link store from an unreadable one, mirroring the diary
    /// repository's rule that a corrupt payload is never silently reported as empty.
    func loadState() -> NutritionRecipeAssociationLoadState {
        guard let data = defaults.data(forKey: Self.storageKey) else { return .absent }
        guard let links = try? JSONDecoder().decode([NutritionRecipeAssociation].self, from: data) else {
            return .corrupt
        }
        return .loaded(links)
    }

    /// Every readable link. Absent reads as none; corrupt stays visible through loadState so
    /// callers can say links are unavailable instead of pretending there are none.
    func associations() -> [NutritionRecipeAssociation] {
        guard case .loaded(let links) = loadState() else { return [] }
        return links
    }

    func association(forEntryID entryID: String) -> NutritionRecipeAssociation? {
        associations().first { $0.entryID == entryID }
    }

    /// Links an entry to a recipe, replacing any existing link for that entry (one recipe per
    /// entry). The recipe name is snapshotted now; nothing else about the recipe is copied.
    func associate(entryID: UUID, recipeID: String, recipeName: String, at: Date = .now) throws {
        var links = try readableLinks()
        links.removeAll { $0.entryID == entryID.uuidString }
        links.append(NutritionRecipeAssociation(entryID: entryID.uuidString, recipeID: recipeID,
                                                recipeName: recipeName, linkedAt: at))
        try save(links)
    }

    func dissociate(entryID: UUID) throws {
        var links = try readableLinks()
        links.removeAll { $0.entryID == entryID.uuidString }
        try save(links)
    }

    /// Drops links whose entry no longer exists. Only this store's own rows are touched; the
    /// diary itself is never modified here.
    ///
    /// PRECONDITION: `keepingEntryIDs` must be the COMPLETE set of entry IDs for the whole
    /// owner data set this store covers, not the currently loaded slice. The storage key is
    /// device-global, so passing a partial set (for example only the entries one screen has
    /// loaded) permanently deletes links whose entries simply were not loaded. This is a
    /// deliberate, owner-scoped cleanup operation only; automatic reload paths must never
    /// call it.
    func pruneOrphans(keepingEntryIDs: Set<String>) throws {
        let links = try readableLinks()
        let kept = links.filter { keepingEntryIDs.contains($0.entryID) }
        if kept.count != links.count { try save(kept) }
    }

    private func readableLinks() throws -> [NutritionRecipeAssociation] {
        switch loadState() {
        case .absent: return []
        case .loaded(let links): return links
        case .corrupt: throw NutritionRecipeAssociationError.storeUnreadable
        }
    }

    private func save(_ links: [NutritionRecipeAssociation]) throws {
        guard loadState() != .corrupt else { throw NutritionRecipeAssociationError.storeUnreadable }
        defaults.set(try JSONEncoder().encode(links), forKey: Self.storageKey)
    }
}
