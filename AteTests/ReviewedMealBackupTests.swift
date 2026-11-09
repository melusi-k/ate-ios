import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Ate

@MainActor
final class ReviewedMealBackupTests: XCTestCase {
    private func meal() -> NutritionDiaryEntry {
        NutritionDiaryEntry(foodName: "Pap", date: Date(timeIntervalSince1970: 1_794_000_000),
            meal: .lunch, quantity: 1, quantityUnit: "portion", servings: 1,
            source: .userProvided, sourceName: "You", nutrientsPerServing: NutritionSnapshot(
                energyKcal: 300, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil),
            dayKey: "2026-11-06")
    }

    func testReviewRetainsExactSelectedBytesAndValues() throws {
        let meal = meal()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode([meal])
        let review = try ReviewedMealBackup(bytes)
        XCTAssertEqual(review.originalBytes, bytes)
        XCTAssertEqual(review.entries, [meal])
    }

    func testInvalidDuplicateImpossibleDayEmptyAndNonMealBackupRefuseReview() throws {
        let entry = meal()
        var invalid = entry; invalid.dayKey = "2026-02-30"
        for entries in [[entry, entry], [invalid], []] {
            XCTAssertThrowsError(try ReviewedMealBackup(JSONEncoder().encode(entries)))
        }
        XCTAssertThrowsError(try ReviewedMealBackup(Data("{\"recipes\":[]}".utf8)))
    }

    func testBoundedFileReadRefusesOversizeWithoutImporting() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(ReviewedMealBackup.maximumBytes + 1))
        try file.close()
        XCTAssertThrowsError(try ReviewedMealBackup.readBytes(from: url))
    }

    func testReadIsAnIndependentCopyNotMutableFileMapping() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try JSONEncoder().encode([meal()])
        try original.write(to: url)
        let review = try ReviewedMealBackup(ReviewedMealBackup.readBytes(from: url))
        try Data("changed file".utf8).write(to: url)
        XCTAssertEqual(review.originalBytes, original)
    }
    func testPickerCancellationIsNotAReadFailure() {
        XCTAssertTrue(ReviewedMealBackup.isPickerCancellation(CocoaError(.userCancelled)))
        XCTAssertFalse(ReviewedMealBackup.isPickerCancellation(CocoaError(.fileReadNoSuchFile)))
    }

    func testActualPickerDelegateCancellationFinishesOnceWithoutSelectedURL() {
        var outcomes: [URL?] = []
        let delegate = MealBackupDocumentPicker.Coordinator { outcomes.append($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)
        delegate.documentPickerWasCancelled(picker)
        delegate.documentPicker(picker, didPickDocumentsAt: [URL(fileURLWithPath: "/late.json")])
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNil(outcomes[0])
    }

    func testActualPickerDelegateSelectionFinishesOnceWithExactURL() {
        var outcomes: [URL?] = []
        let delegate = MealBackupDocumentPicker.Coordinator { outcomes.append($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)
        let selected = URL(fileURLWithPath: "/selected.json")
        delegate.documentPicker(picker, didPickDocumentsAt: [selected])
        delegate.documentPickerWasCancelled(picker)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0], selected)
    }

    func testActualPickerDelegateEmptySelectionIsNoSelectedURL() {
        var outcomes: [URL?] = []
        let delegate = MealBackupDocumentPicker.Coordinator { outcomes.append($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)
        delegate.documentPicker(picker, didPickDocumentsAt: [])
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNil(outcomes[0])
    }

}
