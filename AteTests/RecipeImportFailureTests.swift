import XCTest
@testable import Ate

final class RecipeImportFailureTests: XCTestCase {
    private final class Fallback: BackendService {
        var calls = 0
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            calls += 1
            return RecipeCard(title: "Demo card", source: .mock)
        }
        func publish(_ card: RecipeCard) async throws -> String { "unused" }
        func fetchShared(slug: String) async throws -> RecipeCard? { nil }
    }

    func testOfflineAndTimeoutDoNotBecomeDemoOrSecondFetch() async {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut, .cannotFindHost] {
            for available in [false, true] {
                let fallback = Fallback()
                var fetches = 0
                let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in
                    fetches += 1; throw URLError(code)
                }, modelAvailable: { available })
                do {
                    _ = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/soup"))
                    XCTFail("A failed import must not produce a recipe")
                } catch { XCTAssertEqual((error as? URLError)?.code, code) }
                XCTAssertEqual(fetches, 1, "Do not spend another page timeout after a failed fetch")
                XCTAssertEqual(fallback.calls, 0)
            }
        }
    }

    func testDeadPageAndCancellationStayFailures() async {
        for cancellation in [false, true] {
            let fallback = Fallback()
            let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in
                if cancellation { throw CancellationError() }
                throw BackendError(message: "That page didn't load (HTTP 404). Check the link and try again.")
            }, modelAvailable: { false })
            do {
                _ = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/missing"))
                XCTFail("No card from a dead or cancelled source")
            } catch {
                if cancellation { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertTrue(error.localizedDescription.contains("HTTP 404")) }
            }
            XCTAssertEqual(fallback.calls, 0)
        }
    }

    func testStructuredPageImportsWithoutModelOrFallback() async throws {
        let fallback = Fallback()
        var fetches = 0
        let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in
            fetches += 1; return QAFixtures.jsonLDHTML
        }, modelAvailable: { false })
        let card = try await backend.parseRecipe(.init(mode: .url, text: QAFixtures.jsonLDURL))
        XCTAssertEqual(card.source, .jsonLD)
        XCTAssertEqual(card.sourceURL, QAFixtures.jsonLDURL)
        XCTAssertFalse(card.ingredients.isEmpty)
        XCTAssertFalse(card.steps.isEmpty)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(fallback.calls, 0)
    }

    func testHealthyNonstructuredPageKeepsExplicitDemoFallback() async throws {
        let fallback = Fallback()
        let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in "<html>A recipe article</html>" }, modelAvailable: { false })
        let card = try await backend.parseRecipe(.init(mode: .url, text: "https://recipes.example/article"))
        XCTAssertEqual(card.source, .mock)
        XCTAssertEqual(fallback.calls, 1)
    }

    func testInvalidURLNeverFetchesOrFallsBack() async {
        for link in ["", "not a link", "httpx://recipes.example/a", "https:///", "file:///tmp/recipe", "https://"] {
            let fallback = Fallback()
            var fetches = 0
            let backend = OnDeviceBackend(fallback: fallback, loadPageHTML: { _ in fetches += 1; return "" }, modelAvailable: { false })
            do {
                _ = try await backend.parseRecipe(.init(mode: .url, text: link))
                XCTFail("Invalid link must be actionable failure")
            } catch { XCTAssertTrue(error.localizedDescription.contains("recipe link")) }
            XCTAssertEqual(fetches, 0)
            XCTAssertEqual(fallback.calls, 0)
        }
    }
}
