import XCTest
@testable import Ate

/// Compile the exact UI fixture file in this target as well. No copied recipe.
final class PromptRecipeFixtureTests: XCTestCase {
    private final class RecordingBackend: BackendService {
        var requests: [ParseRequest] = []
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            requests.append(request)
            return RecipeCard(id: "fixture-boundary", title: "Fixture sentinel", source: .mock)
        }
        func publish(_ card: RecipeCard) async throws -> String { XCTFail("No publish"); return "" }
        func fetchShared(slug: String) async throws -> RecipeCard? { XCTFail("No fetch"); return nil }
    }

    func testExactUIFixturesAreVerifiedMeasuredSources() {
        for source in [PromptRecipeFixture.salmon(named: "Miso salmon for two"),
                       PromptRecipeFixture.salmon(named: "Synced stew"),
                       "zzz" + PromptRecipeFixture.salmonContinuation,
                       PromptRecipeFixture.breadSalad] {
            guard case .verified(let contract) = SourceRecipeFidelity.extraction(source) else {
                return XCTFail("The actual UI fixture must verify, not merely look recipe-shaped")
            }
            XCTAssertGreaterThanOrEqual(contract.ingredients.count, 4)
            XCTAssertTrue(contract.ingredients.allSatisfy { $0.quantity > 0 })
            XCTAssertFalse(contract.method.isEmpty)
        }
        XCTAssertTrue(PromptRecipeFixture.salmonContinuation.hasPrefix("\nIngredients\n"))
        XCTAssertTrue(PromptRecipeFixture.salmon(named: "Synced stew").hasPrefix("Synced stew\nIngredients\n"))
        guard case .verified(let salad) = SourceRecipeFidelity.extraction(PromptRecipeFixture.breadSalad) else {
            return XCTFail("Bread salad source must verify")
        }
        XCTAssertTrue(salad.ingredients.contains { $0.name.lowercased().contains("bread") && $0.quantity == 2 })
    }

    func testActualAddBoundaryAcceptsFixtureButStillRefusesNameOnly() async throws {
        let backend = RecordingBackend()
        let source = PromptRecipeFixture.salmon(named: "Synced stew")
        _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: source), using: backend)
        XCTAssertEqual(backend.requests.count, 1)
        XCTAssertEqual(backend.requests.first?.text, source)
        do {
            _ = try await AddPromptSourceImport.parse(ParseRequest(mode: .prompt, text: "Synced stew"), using: backend)
            XCTFail("Fixture repair must not permit names through Add")
        } catch {
            XCTAssertEqual(error.localizedDescription, AddPromptSourceImport.missingSourceMessage)
        }
        XCTAssertEqual(backend.requests.count, 1)
    }
    func testActualUIMockBackendKeepsFixtureFirstLineTitlesCardAndTimers() async throws {
        let backend = MockBackend()
        backend.usesSourceFixtureTitles = true
        for title in ["Pea risotto", "Shareable soup", "Timer test salmon", "Lemon chicken traybake", "Synced stew"] {
            let source = PromptRecipeFixture.salmon(named: title)
            let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: source), using: backend).card
            XCTAssertEqual(card.title, title)
            XCTAssertEqual(card.source, .mock)
            XCTAssertEqual(card.servings, 2)
            XCTAssertEqual(card.timeMinutes, 25)
            XCTAssertEqual(card.ingredients.map(\.name), ["salmon fillets", "white miso", "honey", "garlic", "rice"])
            XCTAssertEqual(card.steps.count, 4)
            XCTAssertEqual(card.steps.map(\.timeSeconds), [nil, nil, 600, 60])
        }
        let padded = "\n  Timer test salmon  \n" + PromptRecipeFixture.salmonContinuation
        let card = try await backend.parseRecipe(.init(mode: .prompt, text: padded))
        XCTAssertEqual(card.title, "Timer test salmon")
    }

}
