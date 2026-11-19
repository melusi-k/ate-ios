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
        let source = "Eggs\nIngredients\n2 eggs\n1 tsp oil\nMethod\n1. Heat the oil for 2 minutes.\n2. Add eggs and cook for 5 minutes."
        guard case .verified = SourceRecipeFidelity.extraction(source) else { return XCTFail("Fixture must be verified") }
        let fallback = RecordingBackend()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { false })
        do {
            _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: source, dishHint: "Eggs"), using: backend)
            XCTFail("Unavailable model must not invent a demo substitute")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No demo recipe was substituted"))
            XCTAssertNotEqual(error.localizedDescription, AddPromptSourceImport.missingSourceMessage)
        }
        XCTAssertTrue(fallback.requests.isEmpty)
        let recording = RecordingBackend()
        _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: source, dishHint: "Eggs"), using: recording)
        XCTAssertEqual(recording.requests.count, 1)
        XCTAssertEqual(recording.requests.first?.text, source)
        XCTAssertEqual(recording.requests.first?.dishHint, "Eggs")
    }

    func testRecognizableUnverifiableRecipeKeepsExistingFailClosedBackendBoundary() async {
        let text = "Ingredients\nSomething impossible\nMethod\nDo something."
        guard case .unverifiable = SourceRecipeFidelity.extraction(text) else { return XCTFail("Fixture must be recognizable") }
        let fallback = RecordingBackend()
        let backend = OnDeviceBackend(fallback: fallback, modelAvailable: { true })
        do {
            _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: text), using: backend)
            XCTFail("Unverifiable source must still fail closed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("couldn't verify"))
        }
        XCTAssertTrue(fallback.requests.isEmpty)
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
