import Foundation

/// Explicit admitted graph dependency, never synthesized from defaults or a fresh
/// generation. Startup must replay before construction and bind every shared writer.
@MainActor
struct RecipeShoppingAuthorityBinding {
    let owner: RecipeShoppingSyncOwner
    let receipt: AccountGenerationPolicy.Receipt
    let journal: RecipeShoppingSyncCommitJournal
    let defaults: UserDefaults
    let session: AuthSession

    func commit(recipes: [RecipeCard], shopping: [ShoppingItem], metadata: RecipeShoppingSyncStage.Metadata) throws {
        try owner.withAdmittedWriterEffect {
            // No network use: prepare's upload plan is ignored for local mutation.
            let checked = try RecipeShoppingSyncStage.prepare(recipes: recipes, shopping: shopping,
                metadata: metadata, remote: [], ownerID: receipt.ownerID)
            let stage = RecipeShoppingSyncStage(recipes: recipes, shopping: shopping,
                metadata: checked.metadata, upload: []) // preserve actual local order
            try journal.commit(stage, receipt: receipt)
        }
    }
}
