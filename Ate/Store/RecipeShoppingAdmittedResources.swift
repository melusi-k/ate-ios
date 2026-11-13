import Foundation
import SwiftData

/// Raw existing-install inventory, not decoded-view emptiness and never implicit
/// adoption. Unknown/foreign/corrupt owner or missing stamps refuses unchanged.
struct RecipeShoppingRawInventory {
    enum Refusal: Error { case missingMetadata, unknownOwner, unreadableRecord, metadataMismatch }
    let image: ArchiveRecipeShoppingImage
    let metadataBytes: Data?

    func validate(ownerID: String) throws -> RecipeShoppingSyncStage.Metadata {
        guard !ownerID.isEmpty else { throw Refusal.unknownOwner }
        guard let bytes = metadataBytes else {
            // This slice does NOT stamp even a verified empty install. Its adoption
            // decision/preservation is separate and must be explicit.
            throw Refusal.missingMetadata
        }
        let metadata = try JSONDecoder().decode(RecipeShoppingSyncStage.Metadata.self, from: bytes)
        guard metadata.userID == ownerID else { throw Refusal.unknownOwner }
        var recipes: [RecipeCard] = [], shopping: [ShoppingItem] = []
        for row in image.recipes {
            let card = try JSONDecoder().decode(RecipeCard.self, from: row.json)
            guard card.id == row.id else { throw Refusal.unreadableRecord }
            recipes.append(card)
        }
        for row in image.shopping {
            let item = try JSONDecoder().decode(ShoppingItem.self, from: row.json)
            guard item.id == row.id else { throw Refusal.unreadableRecord }
            shopping.append(item)
        }
        _ = try RecipeShoppingSyncStage.prepare(recipes: recipes, shopping: shopping,
            metadata: metadata, remote: [], ownerID: ownerID)
        return metadata
    }
}

/// Dormant strict post-admission resource factory. No StoreRecovery move-aside,
/// empty/in-memory fallback, snapshot replay upload, receipt stamping or UI mount.
@MainActor
final class RecipeShoppingAdmittedResources {
    let container: ModelContainer
    let binding: RecipeShoppingAuthorityBinding
    let rawInventory: RecipeShoppingRawInventory

    private init(container: ModelContainer, binding: RecipeShoppingAuthorityBinding,
                 rawInventory: RecipeShoppingRawInventory) {
        self.container = container; self.binding = binding; self.rawInventory = rawInventory
    }

    /// Must be called AFTER owner.pull and successful empty owner.push consume its
    /// admission capture. It does not perform network I/O or revive a refused owner.
    static func open(owner: RecipeShoppingSyncOwner, session: AuthSession,
                     defaults: UserDefaults, commitDirectory: URL,
                     validateWriterRouting: @escaping () throws -> Void,
                     makeContainer: () throws -> ModelContainer) throws -> RecipeShoppingAdmittedResources {
        try owner.withAdmittedWriterEffect {
            try owner.validateBoundSession(session)
            let receipt = try owner.admittedReceipt()
            guard receipt.ownerID == session.userID else { throw RecipeShoppingSyncOwner.Refusal.ownerMismatch }
            // Failure propagates. There is no corruption move-aside or replacement.
            let container = try makeContainer()
            container.mainContext.autosaveEnabled = false
            let journal = try owner.makeCommitJournal(directory: commitDirectory, container: container,
                defaults: defaults, validateWriterRouting: validateWriterRouting)
            _ = try journal.recoverAndProject()
            let raw = RecipeShoppingRawInventory(image: try UnifiedArchiveImportBinding.snapshotRecipeShopping(container),
                metadataBytes: defaults.data(forKey: "ate.sync.v1"))
            _ = try raw.validate(ownerID: receipt.ownerID)
            let binding = RecipeShoppingAuthorityBinding(owner: owner, receipt: receipt, journal: journal,
                defaults: defaults, session: session)
            return RecipeShoppingAdmittedResources(container: container, binding: binding, rawInventory: raw)
        }
    }

    static func open(owner: RecipeShoppingSyncOwner, session: AuthSession,
                     configuration: ModelConfiguration, defaults: UserDefaults, commitDirectory: URL,
                     validateWriterRouting: @escaping () throws -> Void) throws -> RecipeShoppingAdmittedResources {
        try open(owner: owner, session: session, defaults: defaults,
            commitDirectory: commitDirectory, validateWriterRouting: validateWriterRouting,
            makeContainer: { try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: configuration) })
    }
}
