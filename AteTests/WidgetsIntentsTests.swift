import XCTest
import AppIntents
@testable import Ate

final class WidgetLogicTests: XCTestCase {
    private func timer(_ r: String = "r1", step: Int = 0, end: Date?, paused: Int = 300, total: Int = 600) -> TimerSnapshot {
        TimerSnapshot(recipeID: r, recipeTitle: "Mogodu", stepIndex: step, stepCount: 6, stepText: "Simmer for 20 minutes. Stir often",
                      total: total, endDate: end, pausedRemaining: paused)
    }

    func testTimerCommands() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let running = timer(end: now.addingTimeInterval(125))
        var list = TimerMath.apply(.pause, id: "r1#0", to: [running], now: now)
        XCTAssertNil(list[0].endDate)
        XCTAssertEqual(list[0].pausedRemaining, 125)
        list = TimerMath.apply(.pause, id: "r1#0", to: list, now: now)          // no-op when already paused
        XCTAssertEqual(list[0].pausedRemaining, 125)
        list = TimerMath.apply(.toggle, id: "r1#0", to: list, now: now)
        XCTAssertEqual(list[0].endDate, now.addingTimeInterval(125))
        list = TimerMath.apply(.stop, id: "r1#0", to: list, now: now)
        XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(TimerMath.apply(.stop, id: "missing", to: [running], now: now), [running])
    }

    func testResumeFinishedPausedTimerRestartsFromTotal() {
        let now = Date()
        let list = TimerMath.apply(.resume, id: "r1#0", to: [timer(end: nil, paused: 0, total: 90)], now: now)
        XCTAssertEqual(list[0].endDate, now.addingTimeInterval(90))
    }

    func testOrderingRunningFirstAndFinishedDropped() {
        let now = Date()
        let a = timer("a", end: now.addingTimeInterval(500)), b = timer("b", end: now.addingTimeInterval(60))
        let p = timer("p", end: nil), done = timer("d", end: now.addingTimeInterval(-5))
        XCTAssertEqual(TimerMath.ordered([p, a, done, b], now: now).map(\.recipeID), ["b", "a", "p"])
        XCTAssertEqual(TimerMath.next([p, a], now: now)?.recipeID, "a")
    }

    func testKitchenToggle() {
        let now = Date()
        var r = TimerMath.kitchenToggle([], now: now)
        XCTAssertEqual(r.action, "started")
        XCTAssertEqual(r.list.first?.recipeID, TimerMath.quickRecipeID)
        XCTAssertEqual(r.list.first?.endDate, now.addingTimeInterval(TimeInterval(TimerMath.quickSeconds)))
        r = TimerMath.kitchenToggle(r.list, now: now)
        XCTAssertEqual(r.action, "paused")
        XCTAssertNil(r.list.first?.endDate)
        r = TimerMath.kitchenToggle(r.list, now: now)
        XCTAssertEqual(r.action, "resumed")
        XCTAssertEqual(r.list.count, 1)
    }

    func testStepLineAndFormat() {
        let now = Date()
        XCTAssertEqual(WidgetFormat.mmss(760), "12:40")
        XCTAssertEqual(WidgetFormat.mmss(3725), "1:02:05")
        XCTAssertEqual(WidgetFormat.mmss(-3), "00:00")
        let t = TimerSnapshot(recipeID: "r", recipeTitle: "Mogodu", stepIndex: 3, stepCount: 6, stepText: "Simmer. Then stir",
                              total: 1200, endDate: now.addingTimeInterval(760), pausedRemaining: 0)
        XCTAssertEqual(WidgetFormat.stepLine(t, now: now), "Step 4 · Simmer · 12:40 left")
        var p = t; p.endDate = nil; p.pausedRemaining = 61
        XCTAssertEqual(WidgetFormat.stepLine(p, now: now), "Step 4 · Simmer · paused 01:01")
    }

    func testDeepLinksRoundTrip() {
        XCTAssertEqual(WidgetLinks.parse(WidgetLinks.recipe("abc-1")), .recipe("abc-1"))
        XCTAssertEqual(WidgetLinks.parse(WidgetLinks.cook("abc")), .cook("abc"))
        for m in WidgetLinks.AddMode.allCases { XCTAssertEqual(WidgetLinks.parse(WidgetLinks.add(m)), .add(m)) }
        XCTAssertEqual(WidgetLinks.parse(WidgetLinks.shopping), .shopping)
        XCTAssertNil(WidgetLinks.parse(URL(string: "ate://recipe/abc")!))   // shared links keep their old meaning
        XCTAssertNil(WidgetLinks.parse(URL(string: "https://example.com/open/x")!))
    }

    func testInboxDrain() {
        let d = UserDefaults(suiteName: "widget-inbox-\(UUID())")!
        WidgetInbox.setDone("a", true, d); WidgetInbox.setDone("b", true, d); WidgetInbox.setDone("a", false, d)
        WidgetInbox.addItem("  Milk ", d); WidgetInbox.addItem("   ", d)
        WidgetInbox.openLater(WidgetLinks.add(.photo), d)
        let q = WidgetInbox.drain(d)
        XCTAssertEqual(q.shopping, ["a": false, "b": true])
        XCTAssertEqual(q.adds, ["Milk"])
        XCTAssertEqual(q.url, WidgetLinks.add(.photo))
        XCTAssertTrue(WidgetInbox.drain(d).shopping.isEmpty)
    }

    func testSnapshotRoundTripAndTick() {
        let d = UserDefaults(suiteName: "widget-snap-\(UUID())")!
        var s = WidgetSnapshot()
        s.shopping = [.init(id: "1", name: "Milk", done: false), .init(id: "2", name: "Eggs", done: false)]
        s.save(d)
        var back = WidgetSnapshot.load(d)!
        XCTAssertEqual(back, s)
        back.setDone("1", true)
        XCTAssertEqual(back.nextItem?.name, "Eggs")
        XCTAssertEqual(back.openItems.count, 1)
    }
}

@MainActor
final class WidgetSnapshotBuilderTests: XCTestCase {
    private func recipe(_ id: String, _ title: String, fav: Bool = false, created: Double, ings: [String] = [], cooked: Double? = nil) -> RecipeCard {
        var r = RecipeCard(id: id, title: title, timeMinutes: 30, ingredients: ings.map { Ingredient(name: $0, quantity: 1, unit: "") }, createdAt: created)
        r.favorite = fav; r.lastCookedAt = cooked
        return r
    }

    func testSnapshotBuilder() {
        let recipes = (0..<6).map { recipe("r\($0)", "Dish \($0)", fav: $0 < 4, created: Double($0) * 1000) }
        let shop = [ShoppingItem(name: "Milk", quantity: 2, unit: "l"), ShoppingItem(name: "Done", quantity: 0, unit: "", done: true),
                    ShoppingItem(name: "Salt", quantity: 0, unit: "")]
        let s = WidgetSnapshotBuilder.build(recipes: recipes, shopping: shop, health: nil)
        XCTAssertEqual(s.favourites.count, 4)
        XCTAssertTrue(s.favourites.allSatisfy(\.favorite))
        XCTAssertEqual(s.shopping.map(\.name), ["Milk (2 l)", "Salt"])
        XCTAssertEqual(s.recipeCount, 6)
        XCTAssertNotNil(s.pick)
    }

    func testFavouritesTopUpWithRecent() {
        let recipes = [recipe("a", "A", fav: true, created: 1), recipe("b", "B", created: 3), recipe("c", "C", created: 2)]
        XCTAssertEqual(WidgetSnapshotBuilder.favourites(recipes).map(\.id), ["a", "b", "c"])
    }

    func testPickUsesHealthMatch() {
        let recipes = [recipe("s", "Vanilla cake", created: 1, ings: ["sugar", "butter"]),
                       recipe("c", "Grilled chicken bowl", created: 2, ings: ["chicken", "rice"])]
        let p = WidgetSnapshotBuilder.pick(recipes: recipes, health: .recovery)
        XCTAssertEqual(p?.recipeID, "c")
        XCTAssertEqual(p?.healthTitle, HealthState.recovery.title)
    }

    func testPickRotatesDailyAndSkipsRecentlyCooked() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cookedYesterday = (now.timeIntervalSince1970 - 86400) * 1000
        let recipes = [recipe("a", "A", fav: true, created: 1, cooked: cookedYesterday), recipe("b", "B", fav: true, created: 2)]
        for d in 0..<4 {
            XCTAssertEqual(WidgetSnapshotBuilder.pick(recipes: recipes, health: nil, now: now.addingTimeInterval(Double(d) * 86400 / 8))?.recipeID, "b")
        }
        XCTAssertNil(WidgetSnapshotBuilder.pick(recipes: [], health: nil))
        let one = [recipe("x", "X", created: 1)]
        XCTAssertEqual(WidgetSnapshotBuilder.pick(recipes: one, health: nil)?.why, "From your library")
    }
}

@MainActor
final class AppIntentsTests: XCTestCase {
    private func store(_ recipes: [RecipeCard] = []) -> AppStore {
        TimerSnapshot.save([])
        let s = AppStore(context: nil, backend: MockBackend())
        s.recipes = recipes; s.shopping = []
        return s
    }
    private let mogodu = RecipeCard(id: "mog", title: "Mogodu", timeMinutes: 180,
                                    steps: [Step(order: 1, instruction: "Simmer", timeSeconds: 60)])

    func testRecipeEntityAndQuery() async throws {
        let s = store([mogodu, RecipeCard(id: "pap", title: "Pap")])
        XCTAssertTrue(AppStore.current === s)
        let e = RecipeAppEntity(mogodu)
        XCTAssertEqual(e.title, "Mogodu")
        XCTAssertEqual(e.minutes, 180)
        let q = RecipeEntityQuery()
        let byID = try await q.entities(for: ["pap", "nope"])
        XCTAssertEqual(byID.map(\.id), ["pap"])
        let found = try await q.entities(matching: "mogo")
        XCTAssertEqual(found.map(\.id), ["mog"])
        let suggested = try await q.suggestedEntities()
        XCTAssertEqual(suggested.count, 2)
    }

    func testStartCookMode() async throws {
        let s = store([mogodu])
        _ = try await StartCookModeIntent(recipe: RecipeAppEntity(mogodu)).perform()
        XCTAssertEqual(s.cookTarget?.id, "mog")
        s.cookTarget = nil
        _ = try await StartCookModeIntent(recipe: nil).perform()     // falls back to tonight's pick
        XCTAssertEqual(s.cookTarget?.id, "mog")
    }

    func testAddToShoppingList() async throws {
        let s = store()
        _ = try await AddToShoppingListIntent(item: "milk").perform()
        XCTAssertEqual(s.shopping.map(\.name), ["Milk"])
        let g = try await GroceryQuery().entities(matching: "oat milk")
        XCTAssertEqual(g.first?.id, "oat milk")
    }

    func testTonightsPick() async throws {
        _ = store([mogodu])
        _ = try await TonightsPickIntent().perform()
        XCTAssertEqual(QAProbe.shared.lastIntent, "pick:Mogodu")
    }

    func testSearchIntent() async throws {
        let s = store([mogodu])
        s.tab = .settings
        var i = SearchRecipesIntent()
        i.criteria = StringSearchCriteria(term: "tripe")
        _ = try await i.perform()
        XCTAssertEqual(s.pendingSearch, "tripe")
        XCTAssertEqual(s.tab, .library)
    }

    func testWidgetRelaysActOnLiveStore() {
        let s = store()
        s.addManual("Eggs")
        let id = s.shopping[0].id
        IntentRelay.toggleShopping?(id, true)
        XCTAssertTrue(s.shopping[0].done)
        s.setShoppingDone(id, true)            // idempotent
        XCTAssertTrue(s.shopping[0].done)
        XCTAssertEqual(IntentRelay.kitchenToggle?(), "started")
        XCTAssertEqual(s.timers.timers.first?.recipeID, TimerMath.quickRecipeID)
        IntentRelay.timer?(.stop, s.timers.timers[0].id)
        XCTAssertTrue(s.timers.timers.isEmpty)
    }

    func testOpenJournalEntryIntentUsesTrackerRoute() async throws {
        let journal = JournalStore.shared
        XCTAssertTrue(journal.save(prompt: "Shortcut test", text: "Open this journal entry", state: .balanced, recipeIDs: []))
        guard let entry = journal.entries().first(where: { $0.text == "Open this journal entry" }) else {
            XCTFail("Journal fixture should save"); return
        }
        defer { journal.delete(entry) }
        let s = store()
        var intent = OpenJournalEntryIntent()
        intent.target = AteJournalEntryEntity(entry)
        _ = try await intent.perform()
        XCTAssertEqual(s.tab, .tracker)
        XCTAssertEqual(s.trackerPath, [.journal, .journalEntry(entry.id)])
        XCTAssertEqual(QAProbe.shared.lastIntent, "openJournal")
    }

    func testCreateJournalIntentRejectsImagePromptWithoutSaving() async throws {
        let journal = JournalStore.shared
        let before = Set(journal.entries().map(\.id))
        let intent = CreateAteJournalEntryIntent(
            message: AttributedString("A top-down, highly detailed photograph of a bowl of mogodu on a wooden table"),
            title: "Image prompt", entryDate: nil, location: nil, mediaItems: [])
        do {
            _ = try await intent.perform()
            XCTFail("Image-generation prompts must not be saved as journal entries")
        } catch {
            XCTAssertTrue(error is JournalIntentError, "Expected a user-facing journal intent validation error")
            if case JournalIntentError.imagePrompt = error {} else { XCTFail("Expected imagePrompt refusal, got: \(error)") }
        }
        XCTAssertEqual(Set(journal.entries().map(\.id)), before, "Rejected prompts must not create entries")
    }

    func testJournalIntentPayloadKeepsLocationAndMedia() throws {
        let journal = JournalStore.shared
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZV0AAAAASUVORK5CYII=") ?? Data()
        guard let entry = journal.saveFromIntent(title: "Shortcut meal", text: "Ate with friends", date: Date(timeIntervalSince1970: 1_791_000_000),
                                                  state: .balanced, locationName: "Cape Town", latitude: -33.9249, longitude: 18.4241,
                                                  media: [(data: png, ext: "png")]) else {
            XCTFail("Journal intent payload should save"); return
        }
        defer { journal.delete(entry) }
        XCTAssertEqual(entry.locationName, "Cape Town")
        XCTAssertEqual(entry.latitude, -33.9249, accuracy: 0.0001)
        XCTAssertEqual(entry.longitude, 18.4241, accuracy: 0.0001)
        XCTAssertEqual(entry.mediaFileNames.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: JournalStore.mediaURL(entry.mediaFileNames[0]).path))
    }

    func testHistoricalImagePromptCleanupRemovesOldEntry() throws {
        let journal = JournalStore.shared
        let cleanupKey = "ate.journal.imagePromptCleanup.v1"
        let previous = UserDefaults.standard.object(forKey: cleanupKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: cleanupKey) }
            else { UserDefaults.standard.removeObject(forKey: cleanupKey) }
        }
        UserDefaults.standard.set(false, forKey: cleanupKey)
        XCTAssertTrue(journal.save(prompt: "old prompt", text: "A top-down, highly detailed photograph of plated food with shallow depth of field",
                                   state: .balanced, recipeIDs: []))
        guard let oldEntry = journal.entries().first(where: { $0.text.hasPrefix("A top-down, highly detailed photograph") }) else {
            XCTFail("Historical image prompt fixture should save"); return
        }
        journal.removeImagePromptEntriesOnce()
        XCTAssertNil(journal.entry(oldEntry.id), "Historical image prompts should be removed from the local journal")
    }

    func testDeepLinksFromWidgets() {
        let s = store([mogodu])
        s.handle(url: WidgetLinks.recipe("mog"))
        XCTAssertEqual(s.path, [.recipe("mog")])
        s.handle(url: WidgetLinks.add(.prompt))
        XCTAssertEqual(s.quickAdd?.mode, .prompt)
        s.handle(url: WidgetLinks.shopping)
        XCTAssertEqual(s.tab, .shopping)
        s.handle(url: WidgetLinks.cook(TimerMath.quickRecipeID))    // quick timer: no recipe, no not-found
        XCTAssertNil(s.cookTarget)
        s.handle(url: WidgetLinks.cook("mog"))
        XCTAssertEqual(s.cookTarget?.id, "mog")
    }
}
