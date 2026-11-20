import XCTest
import SwiftUI
@testable import Ate

@MainActor
final class RecipeStreamingTests: XCTestCase {
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }
    private func context() -> RecipeDiscoveryContext {
        .init(owner: "owner-a", saved: [RecipeCard(id: "saved", title: "Vegetable Soup",
            ingredients: [.init(name: "carrot", quantity: 2, unit: "pcs")])], cookedIDs: [], cookedRecipes: [])
    }
    private func food(_ title: String = "Berry Bowl") -> RecipeCard {
        var result = RecipeCard(title: title, servings: 0,
            ingredients: [.init(name: "berries", quantity: 0, unit: "")],
            steps: [.init(order: 1, instruction: "Serve the berries.", timeSeconds: nil)], source: .appleIntelligence)
        result.suggestionDraft = true
        return result
    }
    private func snapshot(_ preview: RecipeStreamPreview, name: String) throws {
        let renderer = ImageRenderer(content: StreamPreviewCard(preview: preview)
            .frame(width: 393).padding().environment(\.dynamicTypeSize, .large))
        renderer.scale = 1
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testAddStepsOnlySourceAndJSONLDAreEditableButNoContentIsRefusedAndInputKept() async throws {
        let input = "Tomato soup\nMethod\nSimmer the tomatoes until soft.\nServe the soup hot."
        let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true },
            selectSourceLines: { _ in .init(title: 0, ingredients: [], method: [2, 3]) })
        let card = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: input), using: backend).card
        XCTAssertTrue(card.ingredients.isEmpty)
        XCTAssertTrue(card.isEditableDraft)
        XCTAssertEqual(card.sourceDraft?.text, input)
        XCTAssertTrue(card.sourceDraft?.warnings.contains(where: { $0.contains("No ingredient rows") }) == true)
        XCTAssertTrue(card.steps.contains { $0.instruction.contains("Simmer") })
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Tomato soup","recipeInstructions":["Simmer tomatoes until soft.","Serve hot."]}</script>"#
        let linked = OnDeviceBackend(fallback: MockBackend(), loadPageHTML: { _ in html }, modelAvailable: { false })
        let linkedCard = try await AddPromptSourceImport.parse(.init(mode: .url, text: "https://example.com/soup"), using: linked).card
        XCTAssertTrue(linkedCard.ingredients.isEmpty)
        XCTAssertTrue(linkedCard.isEditableDraft)
        XCTAssertFalse(linkedCard.steps.isEmpty)
        let suite = "RecipeStreamingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let drafts = DraftStore(defaults: defaults, enabled: true)
        let invalid = "Weekly memo\nThe office opens at nine.\nPlease read the agenda."
        drafts.begin(mode: "Prompt", text: invalid, imageData: nil)
        do {
            _ = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: invalid), using: backend)
            XCTFail("No recipe content must not enter review")
        } catch { XCTAssertEqual(drafts.pending?.text, invalid) }
        let noAction = OnDeviceBackend(fallback: MockBackend(),
            loadPageHTML: { _ in html.replacingOccurrences(of: "Simmer tomatoes until soft.", with: "Read the agenda.").replacingOccurrences(of: "Serve hot.", with: "Arrive by nine.") },
            modelAvailable: { false })
        do {
            _ = try await noAction.parseRecipe(.init(mode: .url, text: "https://example.com/memo"))
            XCTFail("The common final gate must also reject empty-ingredient JSON-LD with no cooking action")
        } catch { XCTAssertEqual(drafts.pending?.text, invalid) }
    }

    func testAddPerRequestSnapshotArrivesBeforeCompletionAndCannotBecomeStoredDraft() async throws {
        let input = "Tomato soup\nIngredients\ntomatoes\nMethod\nSimmer tomatoes until soft."
        let gate = Gate(), started = expectation(description: "first snapshot before completion")
        let done = expectation(description: "final returned")
        var live: RecipeStreamPreview?, final: RecipeCard?, calls = 0
        let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true },
            streamSourceLines: { text, publish in
                calls += 1; XCTAssertEqual(text, input)
                publish?(.init(title: "Tomato soup", ingredients: ["tomatoes"]))
                started.fulfill(); await gate.wait()
                return .init(title: 0, ingredients: [2], method: [4])
            })
        Task { @MainActor in
            final = try await AddPromptSourceImport.parse(.init(mode: .prompt, text: input), using: backend,
                onPreview: { live = $0 }).card
            live = nil; done.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertNil(final, "A partial snapshot is not a final card")
        XCTAssertEqual(calls, 1)
        try snapshot(try XCTUnwrap(live), name: "add-partial-before-final-no-save-or-review")
        gate.release(); await fulfillment(of: [done], timeout: 2)
        XCTAssertNil(live)
        XCTAssertEqual(final?.title, "Tomato soup")
        XCTAssertEqual(final?.ingredients.map(\.name), ["tomatoes"])
    }

    func testExploreSnapshotIsReadOnlyUntilFinalAndLateSnapshotCannotReappear() async throws {
        let session = RecipeDiscoverySession(), gate = Gate()
        let started = expectation(description: "streaming"), returned = expectation(description: "final")
        var sink: RecipePreviewHandler?, calls = 0, saves = 0
        let result = food()
        session.requestStreaming(available: true, context: { self.context() }, generate: { _, preview in
            calls += 1; sink = preview
            preview?(.init(title: "Berry Bowl", ingredients: ["berries"]))
            started.fulfill(); await gate.wait(); returned.fulfill(); return result
        })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(session.loading)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertFalse(session.save(result, context: { self.context() }) { _ in saves += 1; return true })
        XCTAssertEqual(saves, 0)
        try snapshot(try XCTUnwrap(session.preview), name: "explore-partial-before-final-no-save-or-review")
        gate.release(); await fulfillment(of: [returned], timeout: 2)
        XCTAssertNil(session.preview)
        XCTAssertEqual(session.suggestions.count, 1)
        XCTAssertEqual(calls, 1)
        sink?(.init(title: "Late leaked preview"))
        XCTAssertNil(session.preview, "A completed first pass cannot publish again")
    }

    func testCancellationDeadlineAccountChangeAndNewRequestIsolateRetainedSinks() async throws {
        for reason in ["cancel", "deadline", "account"] {
            let session = RecipeDiscoverySession(timeoutNanoseconds: reason == "deadline" ? 20_000_000 : 60_000_000_000)
            var input = context(), sink: RecipePreviewHandler?
            let gate = Gate(), started = expectation(description: reason), returned = expectation(description: reason + " returned")
            session.requestStreaming(available: true, context: { input }, generate: { _, preview in
                sink = preview; preview?(.init(title: "Old partial"))
                XCTAssertNotNil(session.preview, "Initial preview must publish synchronously: \(reason)")
                started.fulfill(); await gate.wait(); returned.fulfill(); return self.food("Old result")
            })
            await fulfillment(of: [started], timeout: 2)
            if reason == "deadline" {
                let expired = expectation(description: "deadline revoked publication")
                let observer = Task { @MainActor in
                    while session.loading && !Task.isCancelled { await Task.yield() }
                    if !Task.isCancelled { expired.fulfill() }
                }
                await fulfillment(of: [expired], timeout: 2)
                observer.cancel()
                XCTAssertTrue(session.message?.contains("took too long") == true)
            }
            else if reason == "account" { input.owner = "owner-b"; session.accountChanged() }
            else { session.cancel() }
            XCTAssertNil(session.preview)
            sink?(.init(title: "Stale partial"))
            XCTAssertNil(session.preview)
            let newer = expectation(description: "new request")
            session.requestStreaming(available: true, context: { input }, generate: { _, preview in
                preview?(.init(title: "New partial"))
                sink?(.init(title: "Old sink must not overwrite"))
                XCTAssertEqual(session.preview?.title, "New partial")
                newer.fulfill(); return self.food("New result")
            })
            await fulfillment(of: [newer], timeout: 2)
            gate.release(); await fulfillment(of: [returned], timeout: 2)
            XCTAssertEqual(session.suggestions.map(\.title), ["New result"])
            XCTAssertNil(session.preview)
            XCTAssertTrue(session.savedIDs.isEmpty)
        }
    }

    func testRerunSendsCurrentEditedCardOnceAndPreservesIdentity() async throws {
        var current = food("Edited berry bowl")
        current.ingredients[0].name = "edited raspberries"
        current.coverImage = "kept.jpg"
        var calls = 0, received = ""
        let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true }, streamSuggestion: { prompt, preview in
            calls += 1; received = prompt
            preview?(.init(title: "Improved berry bowl"))
            return self.food("Improved berry bowl")
        })
        XCTAssertEqual(calls, 0, "No automatic rerun")
        let result = try await backend.rerunRecipe(current)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(received.contains("edited raspberries"))
        XCTAssertTrue(received.contains("Edited berry bowl"))
        XCTAssertEqual(result.id, current.id)
        XCTAssertEqual(result.coverImage, current.coverImage)
        XCTAssertEqual(result.title, "Improved berry bowl")
        XCTAssertEqual(current.title, "Edited berry bowl", "Original value is not mutated")
    }

    func testRerunFailureAndTimeoutKeepOriginalAndSuccessReplacesOnlyThatCard() async throws {
        let session = RecipeDiscoverySession(timeoutNanoseconds: 30_000_000)
        let initial = expectation(description: "original")
        session.request(available: true, context: { self.context() }, generate: { _ in initial.fulfill(); return self.food() })
        await fulfillment(of: [initial], timeout: 2)
        let original = try XCTUnwrap(session.suggestions.first)
        let failed = expectation(description: "failed rerun")
        session.requestStreaming(available: true, context: { self.context() }, replacing: original, generate: { _, preview in
            preview?(.init(title: "Never savable failure")); failed.fulfill()
            throw BackendError(message: "Rerun failed. Your original card is kept.")
        })
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(session.suggestions, [original]); XCTAssertNil(session.preview)
        let gate = Gate(), started = expectation(description: "timeout rerun"), returned = expectation(description: "late rerun")
        session.requestStreaming(available: true, context: { self.context() }, replacing: original, generate: { _, preview in
            preview?(.init(title: "Never savable timeout")); started.fulfill()
            await gate.wait(); returned.fulfill(); return self.food("Late result")
        })
        await fulfillment(of: [started], timeout: 2)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(session.suggestions, [original]); XCTAssertNil(session.preview)
        gate.release(); await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(session.suggestions, [original])
        let improved = expectation(description: "improved")
        session.requestStreaming(available: true, context: { self.context() }, replacing: original, generate: { _, _ in
            var result = original; result.steps.append(.init(order: 2, instruction: "Chill before serving.", timeSeconds: nil))
            improved.fulfill(); return result
        })
        await fulfillment(of: [improved], timeout: 2)
        XCTAssertEqual(session.suggestions.count, 1)
        XCTAssertEqual(session.suggestions.first?.id, original.id)
        XCTAssertEqual(session.suggestions.first?.steps.count, 2)
        XCTAssertTrue(session.savedIDs.isEmpty)
    }

    func testRejectedExampleEchoPreviewNeverBecomesSavable() async throws {
        let session = RecipeDiscoverySession(), gate = Gate()
        let started = expectation(description: "echo preview"), returned = expectation(description: "echo rejected")
        var echo = food("Mogodu")
        echo.ingredients = ["beef tripe", "onions", "garlic", "curry powder", "beef stock"].map { .init(name: $0, quantity: 0, unit: "") }
        let backend = OnDeviceBackend(fallback: MockBackend(), modelAvailable: { true }, streamSuggestion: { _, preview in
            preview?(.init(title: "Mogodu", ingredients: echo.ingredients.map(\.name)))
            started.fulfill(); await gate.wait(); returned.fulfill(); return echo
        })
        session.requestStreaming(available: true, context: { self.context() }, generate: { generation, preview in
            try await backend.suggestRecipe(generation, onPreview: preview)
        })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertNotNil(session.preview)
        XCTAssertTrue(session.suggestions.isEmpty)
        gate.release(); await fulfillment(of: [returned], timeout: 2)
        XCTAssertNil(session.preview)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertTrue(session.savedIDs.isEmpty)
        XCTAssertNotNil(session.message)
    }
}
