import Foundation
import SwiftData
import Darwin

/// Explicit personal bytes for both pre-open startup resume and retained-graph
/// reset. No ordinary store constructor, singleton or recovery runs here.
@MainActor
struct FoodJournalResetInventory {
    enum Stores {
        /// Caller guarantees no ordinary container has been opened in this process.
        case unopened(recipeURL: URL, journalURL: URL)
        /// Caller has retired/drained every consumer of these exact containers.
        case retained(recipes: ModelContainer, journal: ModelContainer)
    }
    struct Paths {
        let media: URL
        let legacyDiaryBackups: URL
        let repairDiaryBackups: URL
        let adoptionPreservation: URL
        let covers: URL
        let inboxMedia: URL
        let recipeBackups: URL
        let recoveredExports: URL
        let goalsDirectory: URL
        let control: URL
    }
    let stores: Stores
    let defaults: UserDefaults
    let sharedDefaults: UserDefaults
    let goals: NutritionGoalsStorage
    let paths: Paths

    func components(validate: @escaping () throws -> Void) throws -> ([ClearAllLocalData.Component], Set<String>) {
        try validate()
        let erasedDirectories = [paths.media, paths.legacyDiaryBackups, paths.repairDiaryBackups,
            paths.adoptionPreservation, paths.covers, paths.inboxMedia]
        let protectedDirectories = [paths.control, paths.recipeBackups, paths.recoveredExports, paths.goalsDirectory]
        let allPaths = erasedDirectories + protectedDirectories
        guard allPaths.allSatisfy({ $0.isFileURL && $0 == $0.standardizedFileURL && $0.path != "/" }),
              Set(erasedDirectories).count == erasedDirectories.count,
              !erasedDirectories.contains(where: { parent in
                  allPaths.contains { child in parent != child && child.path.hasPrefix(parent.path + "/") }
                  || protectedDirectories.contains(parent)
              }) else { throw ClearAllLocalData.Error.unsafeDirectory }
        var list: [ClearAllLocalData.Component] = []
        switch stores {
        case .unopened(let recipeURL, let journalURL):
            guard recipeURL != journalURL,
                  [recipeURL, journalURL].allSatisfy({ $0.isFileURL && $0 == $0.standardizedFileURL && $0.path != "/" }) else {
                throw ClearAllLocalData.Error.unsafeDirectory
            }
            try Self.validateAncestors(recipeURL.deletingLastPathComponent())
            try Self.validateAncestors(journalURL.deletingLastPathComponent())
            var recipes = JournalLocalReset.storeFilesComponent(storeFileURL: recipeURL, validateWriterGate: validate)
            recipes = .init(name: "recipe-store-files", erase: recipes.erase, verifyEmpty: recipes.verifyEmpty)
            list.append(recipes)
            list.append(JournalLocalReset.storeFilesComponent(storeFileURL: journalURL, validateWriterGate: validate))
        case .retained(let recipes, let journal):
            list.append(ClearAllLocalData.recipesAndShopping(container: recipes, validateWriterGate: validate))
            list.append(ClearAllLocalData.journal(container: journal, validateWriterGate: validate))
        }
        list.append(ClearAllLocalData.defaults(name: "all-personal-defaults", store: defaults,
            keys: ClearAllDataKeys.standard.union(["ate.sync.v1"]), prefixes: ClearAllDataKeys.standardPrefixes,
            validateWriterGate: validate))
        list.append(ClearAllLocalData.defaults(name: "all-personal-shared-defaults", store: sharedDefaults,
            keys: ClearAllDataKeys.shared, validateWriterGate: validate))
        list.append(ClearAllLocalData.nutritionGoals(storage: goals, validateWriterGate: validate))
        for (name, path) in [("journal-media", paths.media), ("legacy-diary-backups", paths.legacyDiaryBackups),
            ("repair-diary-backups", paths.repairDiaryBackups), ("adoption-preservation", paths.adoptionPreservation),
            ("cover-images", paths.covers), ("share-inbox-media", paths.inboxMedia)] {
            list.append(ClearAllLocalData.directory(name: name, url: path, validateWriterGate: validate))
        }
        list.append(try selectedChildren(name: "recipe-recovery-backups", directory: paths.recipeBackups, validate: validate) {
            $0.hasPrefix("ate-") && ($0.hasSuffix(".store") || $0.hasSuffix(".store-wal") || $0.hasSuffix(".store-shm"))
        })
        list.append(try selectedChildren(name: "recipe-recovered-exports", directory: paths.recoveredExports, validate: validate) {
            $0.hasPrefix("Ate-recovered-") && $0.hasSuffix(".json")
        })
        list.append(try selectedChildren(name: "nutrition-goals-corrupt-backups", directory: paths.goalsDirectory, validate: validate) {
            $0.hasPrefix("nutrition-goals-corrupt-") && $0.hasSuffix(".json")
        })
        // Active AND retired immutable archive records retain full personal before/
        // after images. A confirmed account wipe must not retain either namespace.
        // Minimal generation/lock/reset/receipt control files are never selected.
        list.append(try selectedChildren(name: "archive-personal-recovery-records", directory: paths.control, validate: validate) { name in
            let prefix: String
            if name.hasPrefix("txn-") { prefix = "txn-" }
            else if name.hasPrefix(".resolved-") { prefix = ".resolved-" }
            else { return false }
            let raw = String(name.dropFirst(prefix.count))
            guard let id = UUID(uuidString: raw), id.uuidString == raw else { throw ClearAllLocalData.Error.unsafeDirectory }
            return true
        })
        return (list, Set(list.map(\.name)))
    }

    @discardableResult
    private static func validateAncestors(_ directory: URL) throws -> Bool {
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for part in directory.path.split(separator: "/") {
            cursor.appendPathComponent(String(part), isDirectory: true)
            var info = stat()
            if lstat(cursor.path, &info) != 0 {
                if errno == ENOENT { return false }
                throw ClearAllLocalData.Error.unsafeDirectory
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw ClearAllLocalData.Error.unsafeDirectory }
        }
        return true
    }

    private func selectedChildren(name: String, directory: URL, validate: @escaping () throws -> Void,
                                  select: @escaping (String) throws -> Bool) throws -> ClearAllLocalData.Component {
        guard directory.isFileURL, directory == directory.standardizedFileURL, directory.path != "/" else {
            throw ClearAllLocalData.Error.unsafeDirectory
        }
        func selected() throws -> [URL] {
            // Reuse directory primitive's strict no-link ancestor traversal, without
            // erasing the directory: verifyEmpty would reject unrelated control.
            guard try Self.validateAncestors(directory) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { try select($0.lastPathComponent) }
        }
        return .init(name: name, erase: {
            for item in try selected() {
                try validate()
                // Removal unlinks a selected child symlink, never follows it.
                try FileManager.default.removeItem(at: item)
            }
        }, verifyEmpty: { guard try selected().isEmpty else { throw ClearAllLocalData.Error.notEmpty } })
    }
}
