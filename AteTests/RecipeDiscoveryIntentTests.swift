import XCTest
@testable import Ate

final class RecipeDiscoveryIntentTests: XCTestCase {
    private final class RecordingBackend: BackendService {
        var requests: [ParseRequest] = []
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            requests.append(request)
            return RecipeCard(id: "fallback", title: "Demo", source: .mock)
        }
        func publish(_ card: RecipeCard) async throws -> String { XCTFail("Must not publish"); return "" }
        func fetchShared(slug: String) async throws -> RecipeCard? { XCTFail("Must not fetch"); return nil }
    }
    private func input() -> RecipeDiscoveryGeneration {
        let context = RecipeDiscoveryContext(owner: "a",
            saved: [RecipeCard(id: "soup", title: "Vegetable Soup",
                ingredients: [.init(name: "carrot", quantity: 2, unit: "pcs")])],
            cookedIDs: [], cookedRecipes: [])
        return RecipeDiscoveryGeneration(context: context, suggested: [])
    }

    func testActualDiscoveryPromptTriggersImportRecognitionButTypedDiscoveryReachesGenerationBoundary() async throws {
        let generation = input()
        // Reproduce build 454 with the real assembled prompt and real recognizer.
        guard case .unverifiable = SourceRecipeFidelity.extraction(generation.prompt) else {
            return XCTFail("Device regression fixture must hit the source-recognition collision")
        }
        let fallback = RecordingBackend()
        var calls = 0, modelCalls = 0
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { true }, modelWillGenerate: { modelCalls += 1 },
            createSuggestion: { prompt in
                calls += 1; XCTAssertEqual(prompt, generation.prompt)
                return RecipeCard(title: "Berry Bowl", servings: 0,
                    ingredients: [.init(name: "berries", quantity: 0, unit: "")],
                    steps: [.init(order: 1, instruction: "Serve the berries in a bowl.", timeSeconds: nil)], source: .appleIntelligence)
            })
        let result = try await backend.suggestRecipe(generation)
        XCTAssertEqual(calls, 1); XCTAssertEqual(modelCalls, 1)
        XCTAssertTrue(fallback.requests.isEmpty)
        XCTAssertEqual(result.source, .appleIntelligence)
        XCTAssertEqual(result.servings, 0); XCTAssertNil(result.timeMinutes)
        XCTAssertTrue(result.suggestionDraft == true)
    }

    func testSameWordsPastedByUserStillFailClosedBeforeModelOrFallback() async throws {
        let fallback = RecordingBackend()
        var extractions = 0
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { true }, selectSourceLines: { text in
            extractions += 1; return SourceDraftImport.selection(text)
        })
        let card = try await backend.parseRecipe(ParseRequest(mode: .prompt, text: input().prompt))
        XCTAssertEqual(card.source, .imported)
        XCTAssertEqual(card.sourceDraft?.text, input().prompt)
        XCTAssertEqual(extractions, 1)
        XCTAssertTrue(fallback.requests.isEmpty)
    }

    @MainActor
    func testUnavailableRealBackendCannotPublishDemoAndReportsRetryWithoutSaving() async {
        let fallback = RecordingBackend()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        let context = RecipeDiscoveryContext(owner: "a", saved: [RecipeCard(id: "s", title: "Soup")],
                                             cookedIDs: [], cookedRecipes: [])
        let session = RecipeDiscoverySession()
        let returned = expectation(description: "actual backend boundary returned")
        session.request(available: true, context: { context }, generate: { generation in
            defer { returned.fulfill() }
            return try await backend.suggestRecipe(generation)
        })
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(fallback.requests.count, 0)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertFalse(session.loading)
        XCTAssertTrue(session.message?.contains("not available") == true)
        XCTAssertTrue(session.message?.contains("Nothing was saved") == true)
    }
    func testSuggestionSchemaLeavesOptionalFieldsUnknownAndUsesNoDerivedTimers() throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let value = GenSuggestion(title: "Berry Bowl", description: nil, servings: nil, timeMinutes: nil,
                ingredients: [.init(name: "berries", quantity: nil, unit: nil)],
                steps: ["Chill the berries for 10-20 minutes, then serve."])
            let card = RecipeLogic.normalize(value.card)
            XCTAssertEqual(card.servings, 0)
            XCTAssertNil(card.timeMinutes)
            XCTAssertNil(card.steps[0].timeSeconds)
            XCTAssertEqual(card.ingredients[0].quantity, 0)
            XCTAssertEqual(card.steps[0].instruction, value.steps[0])
            let reloaded = try JSONDecoder().decode(RecipeCard.self, from: JSONEncoder().encode(card))
            XCTAssertEqual(RecipeLogic.normalize(reloaded), card)
        }
        #endif
    }

}
