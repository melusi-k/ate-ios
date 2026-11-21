import XCTest
import SwiftData
import SwiftUI
@testable import Ate

final class VerifiedPasteImportTests: XCTestCase {
    private final class Spy: BackendService {
        var calls = 0
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard { calls += 1; XCTFail("No model/demo/repair call"); throw VerifiedPasteImport.unsupported }
        func publish(_ card: RecipeCard) async throws -> String { calls += 1; XCTFail("No auto-save/share"); return "" }
        func fetchShared(slug: String) async throws -> RecipeCard? { calls += 1; XCTFail("No fetch"); return nil }
    }

    private func imported(_ text: String) async throws -> RecipeCard {
        let spy = Spy()
        var modelCalls = 0
        let backend = OnDeviceBackend(fallback: spy, modelAvailable: {
            XCTFail("Verified paste must return before availability or model allocation")
            return false
        }, modelWillGenerate: { modelCalls += 1; XCTFail("No model or automatic repair") })
        let result = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: text), using: backend)
        XCTAssertEqual(spy.calls, 0)
        XCTAssertEqual(modelCalls, 0)
        XCTAssertNotNil(result.contract)
        return result.card
    }

    func testExactOwnerPasteSurvivesReviewNormalizeTwiceDraftReloadAndExportImport() async throws {
        let card = try await imported(VerifiedPasteFixture.trifle)
        XCTAssertEqual(card.title, "Nespresso Hazelnut Coffee And Chocolate Trifle Recipe")
        XCTAssertEqual(card.servings, 10)
        XCTAssertEqual(card.source, .imported)
        XCTAssertEqual(card.ingredients.count, 28)
        XCTAssertEqual(card.steps.count, 27)
        XCTAssertNil(card.description); XCTAssertTrue(card.tags.isEmpty); XCTAssertNil(card.cuisine)
        XCTAssertNil(card.timeMinutes)
        XCTAssertTrue(card.steps.allSatisfy { $0.timeSeconds == nil })
        XCTAssertEqual(card.pastedSource?.writtenTime, "40-60 Minutes")
        XCTAssertTrue(card.steps[0].instruction.contains("Chocolate Cake\nPreheat the oven to 190°C"))
        XCTAssertTrue(card.steps[8].instruction.hasPrefix("Chocolate Custard\n"))
        XCTAssertTrue(card.steps[15].instruction.hasPrefix("Hazelnut Coffee Cream\n"))
        XCTAssertTrue(card.steps[18].instruction.hasPrefix("Coffee Syrup\n"))
        XCTAssertTrue(card.steps[20].instruction.hasPrefix("Assembly\n"))
        for heading in ["Chocolate Cake", "Chocolate Custard", "Hazelnut Coffee Cream", "Coffee Syrup"] {
            XCTAssertTrue(card.ingredients.contains { $0.name == heading && $0.quantity == 0 }, heading)
        }
        XCTAssertEqual(card.ingredients.filter { $0.name.lowercased().contains("cocoa") }.map(\.quantity), [30, 55])
        XCTAssertTrue(card.ingredients.contains { $0.quantity == 0.25 && $0.unit == "tsp" && $0.name == "salt" })
        XCTAssertTrue(card.ingredients.contains { $0.quantity == 0 && $0.name == "salt" })
        XCTAssertTrue(card.ingredients.contains { $0.quantity == 0 && $0.name.lowercased().contains("chocolate") })
        XCTAssertTrue(card.pastedSource?.ingredientLines.contains("125g butter (½ cup)") == true)
        XCTAssertTrue(card.pastedSource?.ingredientLines.contains("To Garnish\n30g chopped toasted hazelnuts") == true)
        XCTAssertTrue(card.aiNote?.contains("Component headings are kept as unmeasured rows") == true)
        let normalized = RecipeLogic.normalize(RecipeLogic.normalize(card))
        XCTAssertEqual(normalized, card)
        let data = try JSONEncoder().encode([normalized])
        let reloaded = try XCTUnwrap(JSONDecoder().decode([RecipeCard].self, from: data).first)
        XCTAssertEqual(RecipeLogic.normalize(reloaded), card)
        let merged = RecipeLogic.importCards([reloaded], into: [])
        XCTAssertEqual(merged.result.first, card)
        XCTAssertEqual(RecipeLogic.text(for: card), VerifiedPasteFixture.trifle)
        let reimported = try await imported(RecipeLogic.text(for: reloaded))
        XCTAssertEqual(reimported.ingredients, card.ingredients)
        XCTAssertEqual(reimported.steps, card.steps)
        XCTAssertEqual(reimported.servings, 10); XCTAssertNil(reimported.timeMinutes)
        XCTAssertEqual(reimported.pastedSource?.writtenTime, "40-60 Minutes")
        let suite = "VerifiedPasteImportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let draft = DraftStore(defaults: defaults, enabled: true)
        draft.begin(mode: "Prompt", text: VerifiedPasteFixture.trifle, imageData: nil)
        XCTAssertNil(draft.draft, "Parsing alone must not save a draft or library recipe")
        draft.saveDraft(normalized)
        XCTAssertEqual(DraftStore(defaults: defaults, enabled: true).draft, card)
    }

    @MainActor
    func testRealSaveArchiveExportImportKeepsProtectedSource() async throws {
        let card = try await imported(VerifiedPasteFixture.trifle)
        let suite = "VerifiedPasteArchive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let container = try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        @MainActor func store(_ name: String, context: ModelContext? = nil) -> AppStore {
            AppStore(context: context, backend: Spy(),
                nutritionDiaryRepository: NutritionDiaryRepository(defaults: defaults),
                nutritionGoalsRepository: NutritionGoalsRepository(defaults: defaults,
                    storage: FileNutritionGoalsStorage(fileURL: dir.appendingPathComponent(name))))
        }
        // The actual shared review renderer, not a substitute view. These
        // attachments need human pixel inspection; sizes alone do not qualify UI.
        for units in [UnitSystem.metric, .imperial] {
            let renderer = ImageRenderer(content: RecipeCardView(recipe: card, units: units)
                .frame(width: 393).environment(\.dynamicTypeSize, .large))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = "verified-paste-review-\(units)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let source = store("source-goals.json", context: ModelContext(container))
        source.recipes = []; source.shopping = []
        XCTAssertNil(source.recipe(card.id), "Parsing may not auto-save")
        source.add(RecipeLogic.normalize(card), clearPendingDraft: false)
        XCTAssertEqual(source.recipe(card.id), card)
        let diskReload = store("reload-goals.json", context: ModelContext(container))
        XCTAssertEqual(diskReload.recipe(card.id), card, "Real SwiftData Save and new-context reload")
        let data = try diskReload.exportJSON()
        let archive = try JSONDecoder().decode(AteDataArchive.self, from: data)
        XCTAssertEqual(archive.recipes.first, card)
        let destination = store("destination-goals.json")
        destination.recipes = []; destination.shopping = []
        _ = try destination.importJSON(data)
        let saved = try XCTUnwrap(destination.recipe(card.id))
        XCTAssertEqual(saved, card)
        XCTAssertNil(saved.timeMinutes)
        XCTAssertTrue(saved.steps.allSatisfy { $0.timeSeconds == nil })
        XCTAssertEqual(saved.pastedSource?.writtenTime, "40-60 Minutes")
        XCTAssertEqual(RecipeLogic.text(for: saved), VerifiedPasteFixture.trifle)
        let loose = try SourceDraftImport.card(VerifiedPasteFixture.pasta,
            selected: SourceDraftImport.selection(VerifiedPasteFixture.pasta))
        source.add(loose, clearPendingDraft: false)
        let looseReload = store("loose-reload-goals.json", context: ModelContext(container))
        let durableLoose = try XCTUnwrap(looseReload.recipe(loose.id))
        XCTAssertEqual(durableLoose.servings, 0)
        XCTAssertNil(durableLoose.timeMinutes)
        XCTAssertTrue(durableLoose.steps.allSatisfy { $0.timeSeconds == nil })
        XCTAssertEqual(durableLoose.sourceDraft?.text, VerifiedPasteFixture.pasta)
        _ = try destination.importJSON(looseReload.exportJSON())
        XCTAssertEqual(destination.recipe(loose.id), durableLoose)
        XCTAssertFalse(RecipeQuality.needsInput(durableLoose))
        var suggested = RecipeCard(title: "Berry Bowl", servings: 0,
            ingredients: [.init(name: "berries", quantity: 0, unit: "")],
            steps: [.init(order: 1, instruction: "Chill for 10-20 minutes.", timeSeconds: nil)], source: .appleIntelligence)
        suggested.suggestionDraft = true
        source.add(suggested, clearPendingDraft: false)
        let suggestedReload = store("suggestion-reload-goals.json", context: ModelContext(container))
        let durableSuggestion = try XCTUnwrap(suggestedReload.recipe(suggested.id))
        XCTAssertEqual(durableSuggestion.servings, 0)
        XCTAssertNil(durableSuggestion.timeMinutes)
        XCTAssertNil(durableSuggestion.steps[0].timeSeconds)
        try SyncPayloadSafety.validate([SyncRecord(user_id: "owner", kind: "recipe", id: loose.id,
            data: AnyJSON(try JSONEncoder().encode(loose)), updated_at: 1, deleted: false)], owner: "owner")
        let renderer = ImageRenderer(content: RecipeCardView(recipe: durableLoose)
            .frame(width: 393).environment(\.dynamicTypeSize, .large))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "loose-pasta-source-review-unknown-fields"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNBSPAndFractionsUseExactContractWithoutCollapsingRepeatedNames() async throws {
        let source = VerifiedPasteFixture.trifle.replacingOccurrences(of: " ", with: "\u{00A0}")
        let card = try await imported(source)
        XCTAssertEqual(card.ingredients.count, 28); XCTAssertEqual(card.steps.count, 27)
        XCTAssertEqual(card.ingredients.filter { $0.name.contains("castor sugar") }.map(\.quantity), [180, 40])
        XCTAssertEqual(card.ingredients.filter { $0.name.contains("milk") }.map(\.quantity), [225, 1.5])
        XCTAssertEqual(card.servings, 10); XCTAssertNil(card.timeMinutes)
    }

    // Supersedes the old completeness refusals under the simplified import decision.
    func testMissingDuplicateContradictoryRangedAndNonpositiveServingsFailWithoutModel() async throws {
        for value in ["", "0", "-1", "2-4", "2.5", "10\nServes 12", "10 plus 2"] {
            let source = VerifiedPasteFixture.trifle.replacingOccurrences(of: "Serves:\n10", with: value.isEmpty ? "" : "Serves:\n" + value)
            let card = try await imported(source)
            XCTAssertEqual(card.servings, 0)
            XCTAssertTrue(card.sourceDraft?.unknownServings == true)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(RecipeLogic.normalize(card).servings, 0)
            XCTAssertEqual(card.ingredients.count, 28)
        }
    }

    // A truncated or ambiguous source is now reviewable, not fidelity-certified.
    func testTruncatedAmbiguousMissingMethodAndBareNamesRefuseNoSubstitute() async throws {
        for source in [String(VerifiedPasteFixture.trifle.dropLast(15)),
                       VerifiedPasteFixture.trifle.replacingOccurrences(of: "225ml milk", with: "225ml milk, salt"),
                       VerifiedPasteFixture.trifle.components(separatedBy: "\nMethod\n")[0]] {
            let spy = Spy()
            let backend = OnDeviceBackend(fallback: spy, modelAvailable: { false })
            let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: source), using: backend).card
            XCTAssertEqual(card.sourceDraft?.text, source)
            XCTAssertEqual(card.source, .imported)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(spy.calls, 0)
        }
        let spy = Spy()
        do { _ = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: "Eggs Benedict"), using: spy); XCTFail("Bare name") }
        catch { XCTAssertEqual(error.localizedDescription, AddPromptSourceImport.missingSourceMessage) }
        XCTAssertEqual(spy.calls, 0)
    }

    func testEditedSnapshotCannotBypassExistingNormalizationAndLegacyUnchanged() async throws {
        let original = try await imported(VerifiedPasteFixture.trifle)
        var edited = original; edited.steps[0].instruction = "Cook for 2 minutes."
        var forged = edited
        forged.pastedSource?.steps = forged.steps
        XCTAssertFalse(try XCTUnwrap(forged.pastedSource).matches(forged))
        XCTAssertNil(RecipeLogic.normalize(forged).pastedSource)
        var tamperedRows = original
        tamperedRows.pastedSource?.ingredientLines[0] = "Invented ingredient"
        XCTAssertNil(RecipeLogic.normalize(tamperedRows).pastedSource)
        let normalized = RecipeLogic.normalize(edited)
        XCTAssertNil(normalized.pastedSource)
        XCTAssertNil(normalized.steps[0].timeSeconds, "Source drafts never derive timers, even after wording edits")
        for source in [RecipeSource.manual, .appleIntelligence, .mock] {
            var unrelated = edited
            unrelated.pastedSource = nil; unrelated.source = source
            XCTAssertEqual(RecipeLogic.normalize(unrelated).steps[0].timeSeconds, 120)
        }
        for source in [RecipeSource.manual, .appleIntelligence, .imported, .mock] {
            let old = RecipeCard(title: "rice", servings: 0, steps: [.init(order: 9, instruction: "Cook for 2 minutes.", timeSeconds: nil)], source: source)
            let result = RecipeLogic.normalize(old)
            XCTAssertEqual(result.servings, 1)
            XCTAssertEqual(result.steps[0].timeSeconds, 120)
            XCTAssertEqual(result.timeMinutes, 2)
            XCTAssertNil(result.pastedSource)
        }
    }

    func testCancelledActualPasteCannotReturnAndStaleOwnerCannotPublish() async throws {
        let spy = Spy()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let backend = OnDeviceBackend(fallback: spy, modelAvailable: { XCTFail("Cancelled import allocated model"); return false })
                _ = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: VerifiedPasteFixture.trifle), using: backend)
                XCTFail("Cancelled source returned")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertEqual(spy.calls, 0)
        let card = try await imported(VerifiedPasteFixture.trifle)
        let completed = expectation(description: "stale paste refused")
        await MainActor.run {
            let attempt = DraftGenerationAttempt()
            attempt.start { token in
                attempt.invalidate()
                XCTAssertFalse(attempt.publish(token) { XCTFail("Stale verified card published: \(card.title)") })
                completed.fulfill()
            }
        }
        await fulfillment(of: [completed], timeout: 2)
    }
}
