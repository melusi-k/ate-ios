import XCTest
import SwiftData
@testable import Ate

/// Legacy (pre-#245) journal model: the exact shape shipped on main before the unified Food
/// Journal store, without kindRaw/dayKey. Declared module-locally so its SwiftData entity name
/// matches the app's "JournalEntry" on disk; the app's current model is referenced as
/// Ate.JournalEntry everywhere below.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: String
    var createdAt: Date
    var prompt: String
    var text: String
    var stateRaw: String
    var recipeIDs: [String]
    // v1.4.1: Journaling Suggestions provenance.
    var journalingSuggestionTitle: String? = nil
    var momentDate: Date? = nil
    var sourceRaw: String = "ate"
    // b81: location and media from the "New journal entry" intent, plus edit time.
    var locationName: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var mediaFileNames: [String] = []
    var editedAt: Date? = nil
    init(id: String = UUID().uuidString, createdAt: Date = .now, prompt: String, text: String,
         stateRaw: String, recipeIDs: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.prompt = prompt; self.text = text
        self.stateRaw = stateRaw; self.recipeIDs = recipeIDs
    }
}

/// #245 phase 2: schema upgrade safety for the journal container.
@MainActor
final class LegacyJournalStoreUpgradeTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    private var storeURL: URL { dir.appendingPathComponent("journal.store") }

    /// A real on-disk store written by the pre-#245 schema must reopen under the unified schema
    /// with every reflection and its media, recipe, location and moment associations intact.
    /// The app's open path is `try?`, so a failed lightweight migration would silently present
    /// an empty journal; this test fails loudly on any open error or field drift instead.
    func testLegacyJournalStoreReopensUnderUnifiedSchemaWithEveryRecordIntact() throws {
        let legacy = try ModelContainer(for: JournalEntry.self,
                                        configurations: ModelConfiguration(url: storeURL))
        let ctx = legacy.mainContext

        let moment = JournalEntry(prompt: "", text: "Sunset over the spruit",
                                  stateRaw: HealthState.balanced.rawValue)
        moment.sourceRaw = JournalEntrySource.journalMoment.rawValue
        moment.journalingSuggestionTitle = "Walk with Thabo"
        moment.momentDate = Date(timeIntervalSince1970: 1_760_000_000)

        let withMedia = JournalEntry(prompt: "What did you enjoy eating today?",
                                     text: "Mogodu Monday", stateRaw: HealthState.balanced.rawValue)
        withMedia.mediaFileNames = ["img-1.jpg", "img-2.jpg"]
        withMedia.locationName = "Soweto"
        withMedia.latitude = -26.2485
        withMedia.longitude = 27.8540
        withMedia.editedAt = Date(timeIntervalSince1970: 1_790_000_000)

        let withRecipes = JournalEntry(prompt: "Reflect on your day", text: "Cooked the bean curry",
                                       stateRaw: HealthState.performance.rawValue,
                                       recipeIDs: ["recipe-7", "recipe-9"])

        [moment, withMedia, withRecipes].forEach(ctx.insert)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<JournalEntry>()).count, 3)

        // Media files live outside the store (Application Support/JournalMedia in the app);
        // a schema upgrade must never touch them.
        for name in withMedia.mediaFileNames {
            try Data("jpeg-bytes".utf8).write(to: dir.appendingPathComponent(name))
        }

        // Reopen the SAME file under the unified (current app) schema with a plain `try`:
        // any migration failure must fail here, never fall back to an empty container.
        let unified = try ModelContainer(for: Ate.JournalEntry.self, JournalMealPayload.self,
                                         configurations: ModelConfiguration(url: storeURL))
        let rows = try unified.mainContext.fetch(FetchDescriptor<Ate.JournalEntry>())
        XCTAssertEqual(rows.count, 3, "every legacy reflection survives the schema upgrade")

        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let m = try XCTUnwrap(byID[moment.id])
        XCTAssertEqual(m.text, "Sunset over the spruit")
        XCTAssertEqual(m.sourceRaw, JournalEntrySource.journalMoment.rawValue)
        XCTAssertEqual(m.journalingSuggestionTitle, "Walk with Thabo")
        XCTAssertEqual(m.momentDate?.timeIntervalSince1970 ?? 0, 1_760_000_000, accuracy: 0.001)

        let w = try XCTUnwrap(byID[withMedia.id])
        XCTAssertEqual(w.mediaFileNames, ["img-1.jpg", "img-2.jpg"], "media associations survive verbatim")
        XCTAssertEqual(w.locationName, "Soweto")
        XCTAssertEqual(w.latitude ?? 0, -26.2485, accuracy: 0.0001)
        XCTAssertEqual(w.longitude ?? 0, 27.8540, accuracy: 0.0001)
        XCTAssertEqual(w.editedAt?.timeIntervalSince1970 ?? 0, 1_790_000_000, accuracy: 0.001)

        let r = try XCTUnwrap(byID[withRecipes.id])
        XCTAssertEqual(r.recipeIDs, ["recipe-7", "recipe-9"], "recipe associations survive verbatim")
        XCTAssertEqual(r.stateRaw, HealthState.performance.rawValue)

        for row in rows {
            XCTAssertEqual(row.kind, .reflection, "pre-unification rows decode as reflections")
            XCTAssertNil(row.dayKey, "pre-unification rows carry no day key")
        }
        for name in withMedia.mediaFileNames {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path),
                          "media files are untouched by the schema upgrade")
        }

        // The unified store API works on top of the upgraded file.
        let fjStore = FoodJournalStore(container: unified)
        XCTAssertTrue(fjStore.mealEntries().isEmpty, "legacy reflections are not mistaken for meals")
    }
}
