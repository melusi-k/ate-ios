import XCTest
import SwiftData
@testable import Ate

/// Disk reopen without any backend calls. This is not process-kill/iPhone proof.
@MainActor
final class PilotLocalDurabilityTests: XCTestCase {
    func testLocalRecipeShoppingEditsSurviveDiskReopenAndCookHistoryReopens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("pilot.store")
        let suite = "PilotLocalDurability-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Use actual entity disk encoding/readback without constructing the
        // global app graph or a cloud account. No localhost/mock receipt claims.
        do {
            let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            var recipe = RecipeCard(id: "r", title: "Soup")
            recipe.title = "Edited soup"; recipe.favorite = true
            var item = ShoppingItem(id: "s", name: "Beans", quantity: 1, unit: "bag")
            item.quantity = 2; item.done = true
            context.insert(RecipeEntity(id: recipe.id, createdAt: recipe.createdAt, position: 0, json: try JSONEncoder().encode(recipe)))
            context.insert(ShoppingEntity(id: item.id, position: 0, json: try JSONEncoder().encode(item)))
            try context.save()
            let history = CookingHistory(defaults: defaults)
            let date = Date(timeIntervalSince1970: 1_790_000_000)
            try history.recordVerified(recipeID: recipe.id, date: date, dayKey: history.key(for: date))
        }
        let reopened = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(reopened)
        let recipes = try context.fetch(FetchDescriptor<RecipeEntity>())
        let shopping = try context.fetch(FetchDescriptor<ShoppingEntity>())
        XCTAssertEqual(recipes.count, 1); XCTAssertEqual(shopping.count, 1)
        let recipe = try JSONDecoder().decode(RecipeCard.self, from: XCTUnwrap(recipes.first).json)
        let item = try JSONDecoder().decode(ShoppingItem.self, from: XCTUnwrap(shopping.first).json)
        XCTAssertEqual(recipe.title, "Edited soup"); XCTAssertTrue(recipe.favorite)
        XCTAssertEqual(item.quantity, 2); XCTAssertTrue(item.done)
        let history = CookingHistory(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(history.recipeIDs(on: Date(timeIntervalSince1970: 1_790_000_000)), ["r"])
    }
}
