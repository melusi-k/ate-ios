import XCTest
@testable import Ate

@MainActor
final class RoadmapTests: XCTestCase {
    private let card = #"{"id":"one","title":"An idea","summary":"Summary","detail":"Details","status":"considering"}"#
    private func catalog(_ cards: String, version: Int = 1) -> Data {
        Data("{\"schemaVersion\":\(version),\"cards\":[\(cards)]}".utf8)
    }
    private func defaults() -> UserDefaults {
        let name = "RoadmapTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }

    func testCatalogRejectsInvalidSchemaDuplicateIDsBlankCopyUnknownStatusAndMalformedData() throws {
        XCTAssertEqual(try RoadmapCatalog.decode(catalog(card)).cards.first?.title, "An idea")
        for invalid in [catalog(card, version: 2), catalog(card + "," + card),
                        catalog(card.replacingOccurrences(of: "Summary", with: "  ")),
                        catalog(card.replacingOccurrences(of: "considering", with: "tomorrow")),
                        catalog(card.replacingOccurrences(of: "\"one\"", with: "\"bad.id\"")),
                        Data("not json".utf8)] {
            XCTAssertThrowsError(try RoadmapCatalog.decode(invalid))
        }
        XCTAssertTrue(try RoadmapCatalog.decode(catalog("")).cards.isEmpty)
    }

    func testActualBundledCatalogLoadsWithoutNetwork() throws {
        let actual = try XCTUnwrap(RoadmapCatalog.load())
        XCTAssertFalse(actual.cards.isEmpty, "The shipped roadmap must not be a blank catalog")
        XCTAssertEqual(Set(actual.cards.map(\.id)).count, actual.cards.count)
    }

    func testVoteUnvoteAndRelaunchPersistenceWithoutDuplicates() throws {
        let cards = try RoadmapCatalog.decode(catalog(card)).cards
        let storage = defaults()
        let votes = RoadmapVotes(cards: cards, defaults: storage)
        XCTAssertFalse(votes.contains("one"))
        votes.toggle("one")
        XCTAssertNil(votes.error)
        XCTAssertEqual(votes.selected, ["one"])
        let relaunched = RoadmapVotes(cards: cards, defaults: storage)
        XCTAssertTrue(relaunched.contains("one"))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: XCTUnwrap(storage.data(forKey: RoadmapVotes.storageKey))), ["one"])
        relaunched.toggle("one")
        XCTAssertFalse(RoadmapVotes(cards: cards, defaults: storage).contains("one"))
    }

    func testDuplicateStoredIDsBecomeOneAndUnknownIDsArePreservedButCannotBeToggled() throws {
        let cards = try RoadmapCatalog.decode(catalog(card)).cards
        let storage = defaults()
        storage.set(try JSONEncoder().encode(["one", "one", "older-card"]), forKey: RoadmapVotes.storageKey)
        let votes = RoadmapVotes(cards: cards, defaults: storage)
        XCTAssertEqual(votes.selected, ["one", "older-card"])
        votes.toggle("unknown")
        XCTAssertFalse(votes.contains("unknown"))
        votes.toggle("one")
        XCTAssertEqual(votes.selected, ["older-card"])
    }

    func testCorruptLocalPreferencesAreNotOverwrittenOrShownAsSaved() throws {
        let storage = defaults()
        let corrupt = Data("broken".utf8)
        storage.set(corrupt, forKey: RoadmapVotes.storageKey)
        let cards = try RoadmapCatalog.decode(catalog(card)).cards
        let votes = RoadmapVotes(cards: cards, defaults: storage)
        XCTAssertNotNil(votes.error)
        votes.toggle("one")
        XCTAssertFalse(votes.contains("one"))
        XCTAssertEqual(storage.data(forKey: RoadmapVotes.storageKey), corrupt)
    }
}
