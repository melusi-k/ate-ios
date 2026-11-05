import Foundation

enum NutritionMeal: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A local calendar date independent of the time zone used to view the diary later.
enum NutritionDiaryDayKey {
    static func make(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(for key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
}

enum NutritionDiaryNumber {
    /// Parse decimal-pad text using the active locale's decimal separator while
    /// also accepting a period for values copied from labels or older exports.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separator = locale.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

enum NutritionEntrySource: String, CaseIterable, Codable, Identifiable {
    case userProvided, recipeSnapshot, externalFoodRecord
    var id: String { rawValue }
    var title: String {
        switch self {
        case .userProvided: "Entered by you"
        case .recipeSnapshot: "Recipe snapshot"
        case .externalFoodRecord: "External record (not verified by Ate)"
        }
    }

    /// Safe initial provenance text for a newly selected source. External sources
    /// must be named by the person logging the food so we never invent a provider.
    var suggestedSourceName: String {
        switch self {
        case .userProvided: "You"
        case .recipeSnapshot: "Recipe snapshot"
        case .externalFoodRecord: ""
        }
    }

    func accepts(sourceName: String) -> Bool {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if self != .userProvided && name.caseInsensitiveCompare("You") == .orderedSame { return false }
        return true
    }
}

/// Per-serving nutrient snapshot captured at the time the food was explicitly logged.
/// Nil means unknown and must never be replaced with an estimate.
struct NutritionSnapshot: Codable, Equatable {
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?

    subscript(_ field: NutritionGoalField) -> Double? {
        switch field {
        case .energy: energyKcal
        case .protein: proteinGrams
        case .carbohydrates: carbohydratesGrams
        case .fat: fatGrams
        case .fibre: fibreGrams
        }
    }
}

struct NutritionDiaryEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var foodName: String
    var date: Date
    /// Calendar day selected when logged, persisted as YYYY-MM-DD local date.
    var dayKey: String
    var meal: NutritionMeal
    var quantity: Double
    var quantityUnit: String
    var servings: Double
    var source: NutritionEntrySource
    var sourceName: String
    var sourceIdentifier: String
    var verificationNote: String
    var nutrientsPerServing: NutritionSnapshot

    init(id: UUID = UUID(), foodName: String, date: Date, meal: NutritionMeal, quantity: Double,
         quantityUnit: String, servings: Double, source: NutritionEntrySource, sourceName: String,
         sourceIdentifier: String = "", verificationNote: String = "", nutrientsPerServing: NutritionSnapshot,
         dayKey: String? = nil) {
        self.id = id
        self.foodName = foodName
        self.date = date
        self.dayKey = dayKey ?? NutritionDiaryDayKey.make(date)
        self.meal = meal
        self.quantity = quantity
        self.quantityUnit = quantityUnit
        self.servings = servings
        self.source = source
        self.sourceName = sourceName
        self.sourceIdentifier = sourceIdentifier
        self.verificationNote = verificationNote
        self.nutrientsPerServing = nutrientsPerServing
    }

    private enum CodingKeys: String, CodingKey {
        case id, foodName, date, dayKey, meal, quantity, quantityUnit, servings, source, sourceName
        case sourceIdentifier, verificationNote, nutrientsPerServing
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        foodName = try values.decode(String.self, forKey: .foodName)
        date = try values.decode(Date.self, forKey: .date)
        // Existing v1 entries have only an instant. Capture their best available
        // local day once when migrating; all new entries persist dayKey directly.
        dayKey = try values.decodeIfPresent(String.self, forKey: .dayKey) ?? NutritionDiaryDayKey.make(date)
        meal = try values.decode(NutritionMeal.self, forKey: .meal)
        quantity = try values.decode(Double.self, forKey: .quantity)
        quantityUnit = try values.decode(String.self, forKey: .quantityUnit)
        servings = try values.decode(Double.self, forKey: .servings)
        source = try values.decode(NutritionEntrySource.self, forKey: .source)
        sourceName = try values.decode(String.self, forKey: .sourceName)
        sourceIdentifier = try values.decode(String.self, forKey: .sourceIdentifier)
        verificationNote = try values.decode(String.self, forKey: .verificationNote)
        nutrientsPerServing = try values.decode(NutritionSnapshot.self, forKey: .nutrientsPerServing)
    }
}

struct NutritionDayTotals: Equatable {
    let values: [NutritionGoalField: Double?]

    func value(for field: NutritionGoalField) -> Double? {
        values[field] ?? nil
    }

    static func calculate(entries: [NutritionDiaryEntry]) -> NutritionDayTotals {
        var totals: [NutritionGoalField: Double?] = [:]
        for field in NutritionGoalField.allCases {
            guard !entries.isEmpty else { totals[field] = nil; continue }
            var sum = 0.0
            var complete = true
            for entry in entries {
                guard let value = entry.nutrientsPerServing[field], value.isFinite else { complete = false; break }
                sum += value * entry.servings
            }
            totals[field] = complete && sum.isFinite ? roundedTenth(sum) : nil
        }
        return NutritionDayTotals(values: totals)
    }

    /// Rounds to one decimal without overflowing: scaling a large finite sum by 10
    /// can exceed Double.greatestFiniteMagnitude and return infinity to the UI.
    private static func roundedTenth(_ value: Double) -> Double? {
        let scaled = value * 10
        guard scaled.isFinite else { return nil }
        let rounded = scaled.rounded() / 10
        return rounded.isFinite ? rounded : nil
    }
}


enum NutritionDiaryValidation {
    static func isValid(_ entry: NutritionDiaryEntry) -> Bool {
        !entry.foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !entry.quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.quantity.isFinite && entry.quantity > 0
            && entry.servings.isFinite && entry.servings > 0
            && entry.source.accepts(sourceName: entry.sourceName)
            && NutritionGoalField.allCases.allSatisfy { field in
                guard let value = entry.nutrientsPerServing[field] else { return true }
                return value.isFinite && value >= 0
            }
    }
}

enum NutritionDiaryLoadState: Equatable {
    case absent
    case loaded([NutritionDiaryEntry])
    case corrupt
}

enum NutritionDiaryLoadError: LocalizedError {
    case storedDataInvalid

    var errorDescription: String? {
        switch self {
        case .storedDataInvalid:
            return "The saved food diary couldn't be decoded. Saving is disabled until the unreadable data is backed up and reset."
        }
    }
}

enum NutritionDiaryRecoveryError: Error {
    case noCorruptData
    case dataIsValid
}

struct NutritionDiaryRepository {
    let defaults: UserDefaults
    let fileManager: FileManager
    let backupDirectory: URL
    static let storageKey = "ate.nutritionDiary.v1"
    static let corruptBackupDirectoryName = "NutritionDiaryCorruptBackups"

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default,
         backupDirectory: URL? = nil) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.backupDirectory = backupDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Self.corruptBackupDirectoryName, isDirectory: true)
    }

    /// Distinguishes an absent diary from an unreadable one. A corrupt payload is
    /// never silently reported as an empty diary and never overwritten implicitly.
    func loadState() -> NutritionDiaryLoadState {
        guard let data = defaults.data(forKey: Self.storageKey) else { return .absent }
        guard let entries = try? JSONDecoder().decode([NutritionDiaryEntry].self, from: data) else { return .corrupt }
        let legacyRecords = ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]])?
            .contains { $0["dayKey"] == nil } ?? false
        let sorted = entries.sorted {
            $0.dayKey == $1.dayKey ? $0.date > $1.date : $0.dayKey > $1.dayKey
        }
        // Persist migrated keys immediately so a later time-zone change cannot
        // reinterpret legacy entries a second time.
        if legacyRecords, let migrated = try? prepare(sorted) { savePrepared(migrated) }
        return .loaded(sorted)
    }

    func load() -> [NutritionDiaryEntry] {
        guard case .loaded(let entries) = loadState() else { return [] }
        return entries
    }

    /// Encodes a replacement before any related archive state is committed.
    func prepare(_ entries: [NutritionDiaryEntry]) throws -> Data {
        try JSONEncoder().encode(entries)
    }

    /// Commits already-encoded diary data. UserDefaults.set is non-throwing, so
    /// callers can place this after other fallible archive writes.
    func savePrepared(_ data: Data) {
        defaults.set(data, forKey: Self.storageKey)
    }

    func save(_ entries: [NutritionDiaryEntry]) throws {
        // Saving is disabled while unreadable data occupies the store: overwriting
        // it would destroy the only copy of the original diary.
        guard loadState() != .corrupt else { throw NutritionDiaryLoadError.storedDataInvalid }
        savePrepared(try prepare(entries))
    }

    /// Backs up the unreadable payload to an atomically written file before removing
    /// it, so resetting the diary never destroys the only copy. The backup write throws
    /// on failure: if the backup cannot be proven written, the original stays in place.
    func recoverCorruptData() throws {
        guard let data = defaults.data(forKey: Self.storageKey) else { throw NutritionDiaryRecoveryError.noCorruptData }
        guard (try? JSONDecoder().decode([NutritionDiaryEntry].self, from: data)) == nil else { throw NutritionDiaryRecoveryError.dataIsValid }
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent("nutrition-diary-corrupt-\(UUID().uuidString).json")
        try data.write(to: backupURL, options: .atomic)
        defaults.removeObject(forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
