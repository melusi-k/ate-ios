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
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        let result = try await backend.suggestRecipe(generation)
        XCTAssertEqual(fallback.requests.count, 1, "Discovery must reach the existing generation boundary, not import rejection")
        XCTAssertEqual(fallback.requests.first?.text, generation.prompt)
        XCTAssertEqual(fallback.requests.first?.mode, .prompt)
        XCTAssertEqual(result.source, .mock, "This unavailable-model fixture does not pretend to prove live model output")
    }

    func testSameWordsPastedByUserStillFailClosedBeforeModelOrFallback() async {
        let fallback = RecordingBackend()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { true })
        do {
            _ = try await backend.parseRecipe(ParseRequest(mode: .prompt, text: input().prompt))
            XCTFail("An ordinary paste cannot select the typed creative path")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("couldn't verify"))
        }
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
        XCTAssertEqual(fallback.requests.count, 1)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertFalse(session.loading)
        XCTAssertTrue(session.message?.contains("Try again") == true)
        XCTAssertTrue(session.message?.contains("No demo recipe") == true)
    }
}
