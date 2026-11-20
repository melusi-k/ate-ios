import XCTest
@testable import Ate

final class CaptionPasteRecognitionTests: XCTestCase {
    private final class Spy: BackendService {
        var requests: [ParseRequest] = []
        func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
            requests.append(request); throw BackendError(message: "Recording boundary only")
        }
        func publish(_ card: RecipeCard) async throws -> String { XCTFail("No share"); return "" }
        func fetchShared(slug: String) async throws -> RecipeCard? { XCTFail("No fetch"); return nil }
    }

    // Supersedes the earlier refusal-only caption fixture. Recognition remains
    // unverified, but the source is now usable as an editable review draft.
    func testExactPastaNewlinesNBSPIntroAndAmbiguousMethodAreEditableSourceDrafts() async throws {
        let original = VerifiedPasteFixture.pasta
        let variants = [original,
            original.replacingOccurrences(of: "Ingredients:\n", with: "Ingredients:\n\u{00A0}\n"),
            original.replacingOccurrences(of: "Ingredients:", with: "Ingredients:\u{00A0}"),
            original.replacingOccurrences(of: "Ingredients:", with: "Here is the caption's Ingredients:"),
            original.replacingOccurrences(of: "Rigatoni pasta should", with: "Method\nRigatoni pasta should")]
        for source in variants {
            XCTAssertTrue(SourceRecipeFidelity.claimsCaptionSections(source))
            guard case .unverifiable = SourceRecipeFidelity.extraction(source) else {
                XCTFail("Loose caption must never be certified or mistaken for a bare name"); continue
            }
            for available in [false, true] {
                let spy = Spy()
                var modelCalls = 0, selectionCalls = 0
                let backend = OnDeviceBackend(fallback: spy, modelAvailable: { available },
                    modelWillGenerate: { modelCalls += 1 }, selectSourceLines: { raw in
                        selectionCalls += 1; XCTAssertEqual(raw, source)
                        return SourceDraftImport.selection(raw)
                    })
                let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: source), using: backend).card
                XCTAssertEqual(card.source, .imported)
                XCTAssertNil(card.pastedSource, "Loose source is not fidelity-certified")
                XCTAssertEqual(card.sourceDraft?.text, source)
                XCTAssertFalse(card.ingredients.isEmpty)
                XCTAssertFalse(card.steps.isEmpty)
                XCTAssertTrue(card.ingredients.allSatisfy { $0.quantity == 0 })
                XCTAssertEqual(card.servings, 0)
                XCTAssertNil(card.timeMinutes)
                XCTAssertTrue(card.steps.allSatisfy { $0.timeSeconds == nil })
                XCTAssertFalse(RecipeQuality.needsInput(card), "Review warnings may not block Save")
                XCTAssertEqual(modelCalls, available ? 1 : 0)
                XCTAssertEqual(selectionCalls, available ? 1 : 0)
                XCTAssertTrue(spy.requests.isEmpty)
                let rendered = [card.title] + card.ingredients.map(\.name) + card.steps.map(\.instruction)
                for line in SourceDraftImport.lines(source) {
                    XCTAssertTrue(rendered.contains(line), "Never drop or rewrite a source line: \(line)")
                }
                XCTAssertTrue(rendered.contains("1/2 or one whole chicken buillion cube (depends on how salty and flavorful you like it)"))
                let normalized = RecipeLogic.normalize(RecipeLogic.normalize(card))
                XCTAssertEqual(normalized.servings, 0)
                XCTAssertNil(normalized.timeMinutes)
                let reloaded = try JSONDecoder().decode(RecipeCard.self, from: JSONEncoder().encode(normalized))
                XCTAssertEqual(reloaded, normalized)
                XCTAssertEqual(reloaded.sourceDraft?.text, source)
            }
        }
    }

    func testBareNamesURLWrappersAndShortIdeasStillStopBeforeEveryBackend() async {
        for source in ["", "Pasta Papalina", "https://example.com/pasta", "Recipe from https://example.com/pasta",
                       "Pasta idea with cheese and peas", "Ingredients for a quick pasta idea"] {
            XCTAssertFalse(SourceDraftImport.hasSource(source))
            let spy = Spy()
            do {
                _ = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: source), using: spy)
                XCTFail("No-source input reached backend")
            } catch { XCTAssertEqual(error.localizedDescription, AddPromptSourceImport.missingSourceMessage) }
            XCTAssertTrue(spy.requests.isEmpty)
        }
    }

    func testOneFailedExtractionNeverRetriesAndInvalidIndicesCannotInventOrDropFacts() async throws {
        let spy = Spy()
        var calls = 0
        let backend = OnDeviceBackend(fallback: spy, modelAvailable: { true }, selectSourceLines: { _ in
            calls += 1; throw BackendError(message: "One extraction failed")
        })
        let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: VerifiedPasteFixture.pasta), using: backend).card
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(card.sourceDraft?.text, VerifiedPasteFixture.pasta)
        XCTAssertTrue(spy.requests.isEmpty)
        let mapped = try SourceDraftImport.card(VerifiedPasteFixture.pasta,
            selected: .init(title: -10, ingredients: [999, 2, 2, -1], method: [3, 3, 999]))
        let rendered = mapped.ingredients.map(\.name) + mapped.steps.map(\.instruction)
        XCTAssertEqual(rendered.count, SourceDraftImport.lines(VerifiedPasteFixture.pasta).count)
        XCTAssertEqual(Set(rendered), Set(SourceDraftImport.lines(VerifiedPasteFixture.pasta)))
        XCTAssertTrue(mapped.ingredients.allSatisfy { $0.quantity == 0 })
    }

    func testCancelledLooseExtractionCannotReturnAfterAnUncooperativePass() async throws {
        actor Gate {
            var continuation: CheckedContinuation<SourceLineSelection, Never>?
            var entered = false
            func wait() async -> SourceLineSelection {
                entered = true
                return await withCheckedContinuation { continuation = $0 }
            }
            func hasEntered() -> Bool { entered }
            func release() { continuation?.resume(returning: SourceDraftImport.selection(VerifiedPasteFixture.pasta)); continuation = nil }
        }
        let gate = Gate(), spy = Spy()
        let started = expectation(description: "one source extraction started")
        let backend = OnDeviceBackend(fallback: spy, modelAvailable: { true }, selectSourceLines: { _ in
            started.fulfill()
            return await gate.wait()
        })
        let task = Task { try await AddPromptSourceImport.parse(.init(mode: .prompt, text: VerifiedPasteFixture.pasta), using: backend) }
        await fulfillment(of: [started], timeout: 2)
        // The continuation may be installed one executor turn after the spy.
        while !(await gate.hasEntered()) { await Task.yield() }
        task.cancel()
        await gate.release()
        do { _ = try await task.value; XCTFail("Cancelled late extraction returned a review card") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(spy.requests.isEmpty)
    }

    func testReadableLinkAndOCRUseSameSinglePassButEmptySourcesDoNot() async throws {
        for mode in [ParseMode.url, .image] {
            let spy = Spy()
            var calls = 0, reads = 0
            let backend = OnDeviceBackend(fallback: spy, loadPageHTML: { _ in
                reads += 1; return "<html><body>" + VerifiedPasteFixture.pasta.replacingOccurrences(of: "\n", with: "<br>") + "</body></html>"
            }, modelAvailable: { true }, selectSourceLines: { text in
                calls += 1; return SourceDraftImport.selection(text)
            }, readImageText: { _ in reads += 1; return VerifiedPasteFixture.pasta })
            let card = try await AddPromptSourceImport.parse(.init(mode: mode, text: "https://recipes.example/pasta", imageDataUrl: "fixture"), using: backend).card
            XCTAssertEqual(card.source, .imported)
            XCTAssertNotNil(card.sourceDraft)
            XCTAssertEqual(card.servings, 0)
            XCTAssertNil(card.timeMinutes)
            XCTAssertEqual(calls, 1); XCTAssertEqual(reads, 1)
            XCTAssertTrue(spy.requests.isEmpty)
            let empty = OnDeviceBackend(fallback: spy, loadPageHTML: { _ in "<html>Sign in</html>" },
                modelAvailable: { XCTFail("Unreadable source must not allocate a model"); return true },
                readImageText: { _ in "" })
            do {
                _ = try await AddPromptSourceImport.parse(.init(mode: mode, text: "https://recipes.example/pasta", imageDataUrl: "fixture"), using: empty)
                XCTFail("Unreadable source must ask for readable text")
            } catch { XCTAssertTrue(error.localizedDescription.contains("read")) }
        }
    }
}
