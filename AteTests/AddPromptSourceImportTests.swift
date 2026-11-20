import XCTest
@testable import Ate

final class AddPromptSourceImportTests: XCTestCase {
    private final class RecordingBackend: BackendService {
        var requests: [ParseRequest] = []
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            requests.append(request)
            return RecipeCard(id: "sentinel", title: "Backend sentinel", source: .mock)
        }
        func publish(_ card: RecipeCard) async throws -> String { XCTFail("No publish"); return "" }
        func fetchShared(slug: String) async throws -> RecipeCard? { XCTFail("No fetch"); return nil }
    }

    func testTypedNameIdeaAndConfirmedNameNeverInvokeAnyBackendOrReturnInventedCard() async {
        let backend = RecordingBackend()
        for text in ["Eggs Benedict", "  Eggs Benedict\n", "A quick weeknight miso salmon for two", "", "Some entirely unknown dish"] {
            for hint in [nil, "Eggs Benedict"] as [String?] {
                do {
                    _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: text, dishHint: hint), using: backend)
                    XCTFail("No-source Add must not return a review card")
                } catch {
                    XCTAssertEqual(error.localizedDescription, AddPromptSourceImport.missingSourceMessage)
                    XCTAssertTrue(error.localizedDescription.contains("Nothing was generated"))
                    XCTAssertTrue(error.localizedDescription.contains("ingredients and method"))
                }
            }
        }
        XCTAssertTrue(backend.requests.isEmpty, "Includes model, custom and demo backends")
    }

    func testVerifiedFullRecipeIsForwardedByteExactWithConfirmationAndContract() async throws {
        let source = "Eggs\nServes 2\nIngredients\n2 eggs\n1 tsp oil\nMethod\n1. Heat the oil for 2 minutes.\n2. Add eggs and cook for 5 minutes."
        guard case .verified = SourceRecipeFidelity.extraction(source) else { return XCTFail("Fixture must be verified") }
        let fallback = RecordingBackend()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        let imported = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: source, dishHint: "Eggs"), using: backend)
        XCTAssertEqual(imported.card.source, .imported)
        XCTAssertEqual(imported.card.servings, 2)
        XCTAssertNotNil(imported.card.pastedSource)
        XCTAssertNotNil(imported.contract)
        XCTAssertTrue(fallback.requests.isEmpty)
        let recording = RecordingBackend()
        _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: source, dishHint: "Eggs"), using: recording)
        XCTAssertEqual(recording.requests.count, 1)
        XCTAssertEqual(recording.requests.first?.text, source)
        XCTAssertEqual(recording.requests.first?.dishHint, "Eggs")
    }

    func testRecognizableUnverifiableRecipeKeepsExistingFailClosedBackendBoundary() async {
        // Same measured-but-ambiguous source as the existing real recognizer
        // regression. Recognition is independent of whether a full parse succeeds.
        let text = "Mogodu Ingredients 1 kg beef tripe 2 onions salt to taste Method Simmer 150 minutes, fry 5 minutes, season."
        XCTAssertTrue(SourceRecipeFidelity.claimsStructuredRecipe(text))
        XCTAssertNil(SourceRecipeFidelity.structuredRecipe(text))
        guard case .unverifiable = SourceRecipeFidelity.extraction(text) else {
            return XCTFail("Measured ambiguous source must be recognizable but unverifiable")
        }
        // Simplified import supersedes the old complete-layout refusal.
        for available in [false, true] {
            let fallback = RecordingBackend()
            var calls = 0
            let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { available }, selectSourceLines: { raw in
                calls += 1; XCTAssertEqual(raw, text); return SourceDraftImport.selection(raw)
            })
            let card = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: text), using: backend).card
            XCTAssertEqual(card.sourceDraft?.text, text)
            XCTAssertEqual(card.source, .imported)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(calls, available ? 1 : 0)
            XCTAssertTrue(fallback.requests.isEmpty)
        }
    }

    func testLinkImageAndRewriteRequestsKeepTheirExistingBackendRoute() async throws {
        let backend = RecordingBackend()
        for mode in [ParseMode.url, .image, .rewrite] {
            _ = try await AddPromptSourceImport.parse(ParseRequest(mode: mode, text: "sentinel"), using: backend)
        }
        XCTAssertEqual(backend.requests.map(\.mode), [.url, .image, .rewrite])
    }

    func testAlreadyCancelledImportDoesNotInvokeBackend() async {
        let backend = RecordingBackend()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .url, text: "sentinel"), using: backend)
                XCTFail("Cancellation remains terminal")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
        XCTAssertTrue(backend.requests.isEmpty)
    }
}
