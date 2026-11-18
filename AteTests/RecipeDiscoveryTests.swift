import XCTest
@testable import Ate

@MainActor
final class RecipeDiscoveryTests: XCTestCase {
    private func card(_ id: String = "new", _ title: String = "Berry Yogurt Bowl") -> RecipeCard {
        var card = RecipeCard(id: id, title: title, servings: 2, timeMinutes: 5,
            ingredients: [.init(name: "yogurt", quantity: 200, unit: "g"),
                          .init(name: "banana", quantity: 1, unit: "pcs"),
                          .init(name: "strawberries", quantity: 100, unit: "g")],
            steps: [.init(order: 1, instruction: "Slice the banana into rounds.", timeSeconds: nil),
                    .init(order: 2, instruction: "Spoon the yogurt into two bowls.", timeSeconds: nil),
                    .init(order: 3, instruction: "Top the yogurt with banana and sliced strawberries.", timeSeconds: nil)],
            source: .appleIntelligence)
        card.aiConfidence = 0.9
        return card
    }
    private func context() -> RecipeDiscoveryContext {
        RecipeDiscoveryContext(owner: "owner-a", saved: [RecipeCard(id: "saved", title: "Vegetable Soup",
            ingredients: [.init(name: "carrot", quantity: 2, unit: "pcs")])], cookedIDs: ["cooked"],
            cookedRecipes: [.init(recipeID: "deleted-cooked", title: "Crème Soup", cookedDayKey: "2026-11-14")])
    }
    private func request(_ session: RecipeDiscoverySession, context input: RecipeDiscoveryContext? = nil,
                         result: RecipeCard? = nil) async {
        let input = input ?? context(), result = result ?? card()
        let returned = expectation(description: "generation returned")
        session.request(available: true, context: { input }, generate: { request in
            XCTAssertEqual(request.mode, .prompt)
            XCTAssertTrue(request.text?.contains("Vegetable Soup: carrot") == true)
            XCTAssertTrue(request.text?.contains("Crème Soup") == true)
            defer { returned.fulfill() }
            return result
        })
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertFalse(session.loading)
    }

    func testSuggestedRecipesAreConditionedOnSavedTastesAndDoNotSaveUntilExplicitChoice() async throws {
        let session = RecipeDiscoverySession()
        XCTAssertFalse(RecipeQuality.needsInput(card()), RecipeQuality.issues(card()).joined(separator: "; "))
        await request(session)
        XCTAssertEqual(session.suggestions.count, 1)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertNil(session.message)
        var current = context(), writes = 0
        let candidate = try XCTUnwrap(session.suggestions.first)
        XCTAssertTrue(session.save(candidate, context: { current }) { saved in
            writes += 1; current.saved.append(saved); return true
        })
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(current.saved.contains(candidate))
        XCTAssertTrue(session.savedIDs.contains(candidate.id))
        XCTAssertFalse(session.save(candidate, context: { current }) { _ in writes += 1; return true })
        XCTAssertEqual(writes, 1, "Repeated Save must not duplicate a suggestion")
    }

    func testExcludesSavedCookedAndAlreadySuggestedIDsAndNormalizedTitles() {
        let input = context()
        XCTAssertTrue(RecipeDiscovery.excludes(card("saved", "Different name"), context: input))
        XCTAssertTrue(RecipeDiscovery.excludes(card("fresh", "  VEGETABLE--SOUP "), context: input))
        XCTAssertTrue(RecipeDiscovery.excludes(card("cooked", "Different name"), context: input))
        XCTAssertTrue(RecipeDiscovery.excludes(card("fresh", "Creme Soup"), context: input))
        XCTAssertTrue(RecipeDiscovery.excludes(card("new", "Something else"), context: input, suggested: [card()]))
        XCTAssertTrue(RecipeDiscovery.excludes(card("fresh", "berry yogurt bowl"), context: input, suggested: [card()]))
        XCTAssertFalse(RecipeDiscovery.excludes(card(), context: input))
    }

    func testUnavailableOrEmptyCollectionDoesNotInvokeGeneration() {
        let session = RecipeDiscoverySession()
        session.request(available: false, context: { self.context() }, generate: { _ in XCTFail("Unavailable"); return self.card() })
        XCTAssertFalse(session.loading); XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.message?.contains("not available") == true)
        var empty = context(); empty.saved = []
        session.request(available: true, context: { empty }, generate: { _ in XCTFail("No tastes"); return self.card() })
        XCTAssertTrue(session.message?.contains("Save a recipe first") == true)
    }

    func testDemoBadQualityAndExistingRecipesNeverBecomeSuggestions() async {
        var demo = card(); demo.source = .mock
        var incomplete = card(); incomplete.ingredients = []
        var uncertain = card(); uncertain.aiConfidence = 0.4
        let duplicate = card("fresh", "Vegetable Soup")
        for (label, result) in [("mock", demo), ("empty ingredients", incomplete),
                                ("confidence 0.4", uncertain), ("saved title", duplicate)] {
            let session = RecipeDiscoverySession()
            await request(session, result: result)
            XCTAssertTrue(session.suggestions.isEmpty, label)
            XCTAssertNotNil(session.message, label)
            XCTAssertEqual(result.aiConfidence, result == uncertain ? 0.4 : 0.9, "Never inflate identification confidence: " + label)
        }
    }

    func testEmptyGeneratedColdDishNeedsIngredientsButDoesNotImposeMinimumCountOnOtherCards() {
        var empty = card()
        empty.ingredients = []
        XCTAssertTrue(RecipeQuality.issues(empty).contains("The generated recipe needs measured ingredients."))
        XCTAssertTrue(RecipeQuality.needsInput(empty))
        XCTAssertFalse(RecipeQuality.needsInput(card()), "The complete cold bowl must remain accepted")
        for source in [RecipeSource.manual, .jsonLD, .imported] {
            empty.source = source
            XCTAssertFalse(RecipeQuality.issues(empty).contains("The generated recipe needs measured ingredients."))
        }
        var oneIngredient = card()
        oneIngredient.ingredients = [.init(name: "banana", quantity: 1, unit: "pcs")]
        oneIngredient.steps = [.init(order: 1, instruction: "Slice the banana into rounds.", timeSeconds: nil)]
        XCTAssertFalse(RecipeQuality.issues(oneIngredient).contains("The generated recipe needs measured ingredients."),
                       "This fix rejects an empty list, not all simple single-ingredient preparations")
    }

    func testSaveRechecksCurrentCollectionCookingAndAccountAndReportsWriteRefusal() async throws {
        let session = RecipeDiscoverySession()
        await request(session)
        let candidate = try XCTUnwrap(session.suggestions.first)
        var current = context()
        current.cookedRecipes.append(.init(recipeID: "other-id", title: candidate.title, cookedDayKey: "2026-11-14"))
        XCTAssertFalse(session.save(candidate, context: { current }) { _ in XCTFail("Already cooked"); return true })
        XCTAssertFalse(session.save(candidate, context: { self.context() }) { _ in false })
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertTrue(session.message?.contains("could not be added") == true)
        current = context(); current.owner = "owner-b"
        XCTAssertFalse(session.save(candidate, context: { current }) { _ in XCTFail("Wrong owner"); return true })
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.message?.contains("account changed") == true)
    }

    func testContextReadFailureDoesNotGenerateOrWrite() {
        let session = RecipeDiscoverySession()
        session.request(available: true, context: { throw BackendError(message: "History unavailable") },
            generate: { _ in XCTFail("Unreadable history"); return self.card() })
        XCTAssertEqual(session.message, "History unavailable")
        XCTAssertTrue(session.suggestions.isEmpty)
    }

    func testCancellationSuppressesLateBackendAndDoesNotAutoSave() async {
        let session = RecipeDiscoverySession()
        var continuation: CheckedContinuation<RecipeCard, Never>?
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        session.request(available: true, context: { self.context() }, generate: { _ in
            started.fulfill()
            let result = await withCheckedContinuation { continuation = $0 }
            returned.fulfill(); return result
        })
        await fulfillment(of: [started], timeout: 2)
        session.cancel()
        continuation?.resume(returning: card())
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertFalse(session.loading)
    }

    func testOwnerChangeDuringGenerationRefusesLateSuggestion() async {
        let session = RecipeDiscoverySession()
        var current = context(), continuation: CheckedContinuation<RecipeCard, Never>?
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        session.request(available: true, context: { current }, generate: { _ in
            started.fulfill()
            let result = await withCheckedContinuation { continuation = $0 }
            returned.fulfill(); return result
        })
        await fulfillment(of: [started], timeout: 2)
        current.owner = "owner-b"
        continuation?.resume(returning: card())
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertFalse(session.loading)
    }
    func testGenerationFailureIsTerminalWithoutRetriesOrMockSubstitution() async {
        let session = RecipeDiscoverySession()
        let returned = expectation(description: "failed")
        var calls = 0
        session.request(available: true, context: { self.context() }, generate: { _ in
            calls += 1
            defer { returned.fulfill() }
            throw BackendError(message: "AI assets unavailable")
        })
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(session.message, "AI assets unavailable")
        XCTAssertFalse(session.loading)
        XCTAssertTrue(session.suggestions.isEmpty)
    }

    func testDeadlineIsTerminalAndLateUncooperativeResultCannotPublish() async throws {
        let session = RecipeDiscoverySession(timeoutNanoseconds: 1_000_000)
        var continuation: CheckedContinuation<RecipeCard, Never>?
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        session.request(available: true, context: { self.context() }, generate: { _ in
            started.fulfill()
            let result = await withCheckedContinuation { continuation = $0 }
            returned.fulfill(); return result
        })
        await fulfillment(of: [started], timeout: 2)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(session.loading)
        XCTAssertTrue(session.message?.contains("took too long") == true)
        continuation?.resume(returning: card())
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.message?.contains("took too long") == true)
    }

    func testCollectionChangedWhileGeneratingIsRecheckedBeforeShowingResult() async {
        let session = RecipeDiscoverySession()
        var current = context(), continuation: CheckedContinuation<RecipeCard, Never>?
        let started = expectation(description: "started"), returned = expectation(description: "returned")
        session.request(available: true, context: { current }, generate: { _ in
            started.fulfill()
            let result = await withCheckedContinuation { continuation = $0 }
            returned.fulfill(); return result
        })
        await fulfillment(of: [started], timeout: 2)
        current.saved.append(card("saved-elsewhere"))
        continuation?.resume(returning: card())
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.message?.contains("already saved or cooked") == true)
    }

    func testRenamedExactContentAndUnboundedPromptContextAreRefused() {
        var input = context()
        input.saved.append(card("saved-bowl", "Breakfast Bowl"))
        XCTAssertTrue(RecipeDiscovery.excludes(card(), context: input))
        input.saved = (0..<100).map { RecipeCard(id: "r\($0)", title: String(repeating: "x", count: 1000)) }
        XCTAssertLessThan(RecipeDiscovery.prompt(context: input, suggested: []).count, 5000)
    }

}
