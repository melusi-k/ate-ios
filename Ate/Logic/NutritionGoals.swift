import Foundation

struct DailyNutritionGoals: Codable, Equatable {
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var fibreGrams: Double?

    static let defaultsKey = "ate.nutritionGoals.v1"

    subscript(field: NutritionGoalField) -> Double? {
        get {
            switch field {
            case .energy: energyKcal
            case .protein: proteinGrams
            case .carbohydrates: carbohydratesGrams
            case .fat: fatGrams
            case .fibre: fibreGrams
            }
        }
        set {
            switch field {
            case .energy: energyKcal = newValue
            case .protein: proteinGrams = newValue
            case .carbohydrates: carbohydratesGrams = newValue
            case .fat: fatGrams = newValue
            case .fibre: fibreGrams = newValue
            }
        }
    }

    var isEmpty: Bool {
        energyKcal == nil && proteinGrams == nil && carbohydratesGrams == nil
            && fatGrams == nil && fibreGrams == nil
    }
}

enum NutritionGoalField: String, CaseIterable, Identifiable {
    case energy, protein, carbohydrates, fat, fibre

    var id: String { rawValue }
    var title: String {
        switch self {
        case .energy: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fat: "Fat"
        case .fibre: "Fibre"
        }
    }
    var unit: String { self == .energy ? "kcal" : "g" }
    var maximum: Double { self == .energy ? 100_000 : 10_000 }
    var allowsFractionalValue: Bool { self != .energy }
    var accessibilityName: String { "\(title) daily goal, \(unit)" }
}

enum NutritionGoalValidation {
    static func error(for field: NutritionGoalField, text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a \(field.unit) target or turn this goal off." }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite else { return "Enter a valid number." }
        guard value > 0 else { return "Enter a value greater than zero." }
        guard value <= field.maximum else {
            return "Enter a value no greater than \(Int(field.maximum)) \(field.unit)."
        }
        if !field.allowsFractionalValue, value.rounded() != value {
            return "Energy must be a whole number of kcal."
        }
        if field.allowsFractionalValue, (value * 10).rounded() != value * 10 {
            return "Use no more than one decimal place."
        }
        return nil
    }

    static func number(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// Storage operations deliberately throw so callers can preserve the previous saved configuration on failure.
protocol NutritionGoalsStorage {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func preserveCorruptData(_ data: Data) throws
    func remove() throws
}

enum NutritionGoalsRecoveryError: Error {
    case noCorruptData
    case dataIsValid
}


enum NutritionGoalsLoadError: LocalizedError {
    case storageReadFailed(fallback: DailyNutritionGoals?)
    case storedDataInvalid(fallback: DailyNutritionGoals?)
    case legacyDataInvalid
    case migrationWriteFailed(fallback: DailyNutritionGoals)

    var canRecoverCorruptData: Bool {
        switch self {
        case .storedDataInvalid, .legacyDataInvalid: true
        case .storageReadFailed, .migrationWriteFailed: false
        }
    }

    var fallbackGoals: DailyNutritionGoals? {
        switch self {
        case .storageReadFailed(let fallback), .storedDataInvalid(let fallback):
            return fallback
        case .legacyDataInvalid:
            return nil
        case .migrationWriteFailed(let fallback):
            return fallback
        }
    }

    var errorDescription: String? {
        switch self {
        case .storageReadFailed:
            return "Saved nutrition goals couldn't be read safely. Saving is disabled to protect existing data. Retry loading or cancel."
        case .storedDataInvalid:
            return "The saved nutrition-goals file couldn't be decoded. Saving is disabled until the data can be recovered. Retry loading or cancel."
        case .legacyDataInvalid:
            return "The previous nutrition-goals data couldn't be decoded. Saving is disabled to avoid overwriting it. Cancel and retry after resolving the storage issue."
        case .migrationWriteFailed:
            return "Your existing goals were recovered, but couldn't be migrated to local storage. Saving is disabled until migration succeeds. Retry loading or cancel."
        }
    }
}

/// Atomic file storage avoids treating UserDefaults.set (which has no failure result) as durable success.
struct FileNutritionGoalsStorage: NutritionGoalsStorage {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Ate", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("nutrition-goals-v1.json")
        }
    }

    func read() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func write(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func preserveCorruptData(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let backupURL = directory.appendingPathComponent("nutrition-goals-corrupt-\(UUID().uuidString).json")
        try data.write(to: backupURL, options: .atomic)
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

struct NutritionGoalsRepository {
    let defaults: UserDefaults
    let storage: NutritionGoalsStorage

    init(defaults: UserDefaults = .standard, storage: NutritionGoalsStorage? = nil) {
        self.defaults = defaults
        self.storage = storage ?? FileNutritionGoalsStorage()
    }

    func load() throws -> DailyNutritionGoals {
        let empty = DailyNutritionGoals(
            energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil, fatGrams: nil, fibreGrams: nil
        )
        let legacyData = defaults.data(forKey: DailyNutritionGoals.defaultsKey)
        let legacyGoals = legacyData.flatMap {
            try? JSONDecoder().decode(DailyNutritionGoals.self, from: $0)
        }

        let storedData: Data?
        do {
            storedData = try storage.read()
        } catch {
            // Do not report a transient read failure as an empty configuration or permit an overwrite.
            throw NutritionGoalsLoadError.storageReadFailed(fallback: legacyGoals)
        }

        if let storedData {
            do {
                return try JSONDecoder().decode(DailyNutritionGoals.self, from: storedData)
            } catch {
                // Keep a recoverable legacy copy visible, but require a successful reload before saving.
                throw NutritionGoalsLoadError.storedDataInvalid(fallback: legacyGoals)
            }
        }

        guard let legacyData else { return empty }
        guard let legacyGoals else { throw NutritionGoalsLoadError.legacyDataInvalid }

        do {
            try storage.write(legacyData)
        } catch {
            // The legacy copy is the only known-good value; require a retry before allowing a save/clear.
            throw NutritionGoalsLoadError.migrationWriteFailed(fallback: legacyGoals)
        }
        defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
        return legacyGoals
    }
    /// Preserves malformed stored/legacy bytes before removing them. A valid configuration is never reset.
    func recoverCorruptData() throws {
        let legacyData = defaults.data(forKey: DailyNutritionGoals.defaultsKey)
        let storedData = try storage.read()
        var preservedCorruptData = false

        if let storedData {
            if (try? JSONDecoder().decode(DailyNutritionGoals.self, from: storedData)) != nil {
                throw NutritionGoalsRecoveryError.dataIsValid
            }
            try storage.preserveCorruptData(storedData)
            try storage.remove()
            preservedCorruptData = true
        }

        if let legacyData {
            if (try? JSONDecoder().decode(DailyNutritionGoals.self, from: legacyData)) == nil {
                try storage.preserveCorruptData(legacyData)
                defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
                preservedCorruptData = true
            } else if storedData == nil {
                throw NutritionGoalsRecoveryError.dataIsValid
            }
        }

        guard preservedCorruptData else { throw NutritionGoalsRecoveryError.noCorruptData }
    }

    func save(_ goals: DailyNutritionGoals) throws {
        if goals.isEmpty {
            try storage.remove()
            defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
            return
        }
        let data = try JSONEncoder().encode(goals)
        try storage.write(data)
        // Remove the legacy copy only after the new atomic write succeeded.
        defaults.removeObject(forKey: DailyNutritionGoals.defaultsKey)
    }
}
