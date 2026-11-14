import Foundation

/// Pure proposal. Nothing mutates AppStore or disk until original-generation upload
/// succeeds AND session/lease/receipt/local revision still match the staged snapshot.
struct RecipeShoppingSyncStage {
    struct Metadata: Codable, Equatable {
        var recipeStamps: [String: Double] = [:]
        var recipeTombs: [String: Double] = [:]
        var shopStamps: [String: Double] = [:]
        var shopTombs: [String: Double] = [:]
        var userID: String?
    }
    enum Refusal: Error { case foreignOwner, invalidPayload, invalidStamp }
    let recipes: [RecipeCard]
    let shopping: [ShoppingItem]
    let metadata: Metadata
    let upload: [SyncRecord]

    static func prepare(recipes localRecipes: [RecipeCard], shopping localShopping: [ShoppingItem],
                        metadata local: Metadata, remote: [SyncRecord], ownerID: String) throws -> Self {
        guard !ownerID.isEmpty, local.userID == nil || local.userID == ownerID,
              remote.allSatisfy({ $0.user_id == ownerID && ($0.kind == "recipe" || $0.kind == "shopping") }) else {
            throw Refusal.foreignOwner
        }
        var remoteIdentities = Set<Data>()
        for row in remote {
            guard !row.id.isEmpty, row.updated_at >= 0,
                  remoteIdentities.insert(try JSONEncoder().encode([row.kind, row.id])).inserted else {
                throw Refusal.invalidPayload
            }
            if row.deleted { continue }
            guard let bytes = row.data?.raw else { throw Refusal.invalidPayload }
            if row.kind == "recipe" {
                guard let card = try? JSONDecoder().decode(RecipeCard.self, from: bytes), card.id == row.id else {
                    throw Refusal.invalidPayload
                }
            } else {
                guard let item = try? JSONDecoder().decode(ShoppingItem.self, from: bytes),
                      item.id == row.id, item.quantity.isFinite else { throw Refusal.invalidPayload }
            }
        }
        let allStamps = Array(local.recipeStamps.values) + Array(local.recipeTombs.values)
            + Array(local.shopStamps.values) + Array(local.shopTombs.values)
        guard allStamps.allSatisfy({ $0.isFinite && $0 >= 0 && $0.rounded() < Double(Int64.max) }),
              localRecipes.allSatisfy({ local.recipeStamps[$0.id] != nil }),
              localShopping.allSatisfy({ local.shopStamps[$0.id] != nil }) else { throw Refusal.invalidStamp }
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var recipeBytes: [String: Data] = [:], shoppingBytes: [String: Data] = [:]
        for card in localRecipes {
            guard recipeBytes[card.id] == nil else { throw Refusal.invalidPayload }
            recipeBytes[card.id] = try encoder.encode(card)
        }
        for item in localShopping {
            guard shoppingBytes[item.id] == nil else { throw Refusal.invalidPayload }
            shoppingBytes[item.id] = try encoder.encode(item)
        }
        let recipesResult = SyncMerge.merge(local: .init(data: recipeBytes, stamps: local.recipeStamps,
            tombstones: local.recipeTombs), remote: remote.filter { $0.kind == "recipe" })
        let shoppingResult = SyncMerge.merge(local: .init(data: shoppingBytes, stamps: local.shopStamps,
            tombstones: local.shopTombs), remote: remote.filter { $0.kind == "shopping" })
        var recipes: [RecipeCard] = []
        for (id, bytes) in recipesResult.data {
            let card = try decoder.decode(RecipeCard.self, from: bytes)
            guard card.id == id else { throw Refusal.invalidPayload }
            recipes.append(card)
        }
        recipes.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
        var shoppingByID: [String: ShoppingItem] = [:]
        for (id, bytes) in shoppingResult.data {
            let item = try decoder.decode(ShoppingItem.self, from: bytes)
            guard item.id == id, item.quantity.isFinite else { throw Refusal.invalidPayload }
            shoppingByID[id] = item
        }
        var shopping = localShopping.compactMap { shoppingByID.removeValue(forKey: $0.id) }
        for id in shoppingByID.keys.sorted() { shopping.append(shoppingByID[id]!) }
        var proposed = local
        proposed.userID = ownerID
        proposed.recipeStamps = recipesResult.stamps; proposed.recipeTombs = recipesResult.tombstones
        proposed.shopStamps = shoppingResult.stamps; proposed.shopTombs = shoppingResult.tombstones
        var upload: [SyncRecord] = []
        func append(_ kind: String, _ result: SyncMerge.Result) throws {
            for (ids, deleted) in [(result.push, false), (result.pushDeletes, true)] {
                for id in ids {
                    let stamp = deleted ? result.tombstones[id] : result.stamps[id]
                    guard let stamp, stamp.isFinite, stamp >= 0, stamp.rounded() < Double(Int64.max) else {
                        throw Refusal.invalidStamp
                    }
                    upload.append(SyncRecord(user_id: ownerID, kind: kind, id: id,
                        data: deleted ? nil : result.data[id].map { AnyJSON($0) },
                        updated_at: Int64(stamp.rounded()), deleted: deleted))
                }
            }
        }
        try append("recipe", recipesResult); try append("shopping", shoppingResult)
        return Self(recipes: recipes, shopping: shopping, metadata: proposed, upload: upload)
    }
}
