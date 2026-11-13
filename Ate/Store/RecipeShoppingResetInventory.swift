import Foundation
import SwiftData
import Darwin

/// Dormant standalone account-wide erase list. No erase is run here. All paths and
/// domains are REQUIRED from retained actual resources, never process-global fallbacks.
/// JournalLocalReset erases existing personal Journal data without activating Food Journal.
@MainActor
struct RecipeShoppingResetInventory {
    enum Refusal: Error { case incompletePaths, unsafePath }
    struct Paths {
        let commitDirectory: URL
        let legacyPreservationDirectory: URL
        let recipeBackupDirectory: URL
        let journalBackupDirectory: URL
        let recoveredExportDirectory: URL
        let temporaryExportDirectory: URL
        let sharedInboxDirectory: URL
        let sharedCoverDirectory: URL
        let appOnlyCoverDirectory: URL
        let archiveControlDirectory: URL
        let cacheDirectory: URL
    }
    let recipes: ModelContainer?
    let journal: JournalLocalReset
    let authorityDefaults: UserDefaults
    let legacyStandardDefaults: UserDefaults
    let sharedDefaults: UserDefaults
    let paths: Paths
    private static let ownNames: Set<String> = ["recipes-shopping", "standalone-authority-defaults", "standalone-legacy-defaults",
        "standalone-shared-defaults", "recipe-shopping-sync-commit", "legacy-recipe-shopping-preservation", "recipe-store-backups",
        "journal-store-backups", "recovered-recipe-exports", "temporary-personal-exports", "shared-inbox-files",
        "shared-cover-files", "app-only-cover-files", "archive-personal-transactions", "qa-mock-server-cache"]

    func components(validateResetGate: @escaping () throws -> Void) throws -> ([ClearAllLocalData.Component], Set<String>) {
        guard journal.preservationDirectory != nil, paths.commitDirectory.lastPathComponent == RecipeShoppingSyncCommitJournal.directoryName,
              paths.recipeBackupDirectory.lastPathComponent == "Backups", paths.journalBackupDirectory.lastPathComponent == "Backups",
              paths.sharedInboxDirectory.lastPathComponent == "Inbox", paths.sharedCoverDirectory.lastPathComponent == "Covers",
              paths.appOnlyCoverDirectory.lastPathComponent == "Covers" else { throw Refusal.incompletePaths }
        let (journalComponents, journalRequired) = try journal.components(validateWriterGate: validateResetGate)
        var list = journalComponents
        list.append(ClearAllLocalData.recipesAndShopping(container: recipes, validateWriterGate: validateResetGate))
        // SyncMeta is personal state/tombstones, unlike the minimal generation receipt.
        let allKeys = ClearAllDataKeys.standard.union(ClearAllDataKeys.shared).union(["ate.sync.v1"])
        for (name, store) in [("standalone-authority-defaults", authorityDefaults),
                              ("standalone-legacy-defaults", legacyStandardDefaults), ("standalone-shared-defaults", sharedDefaults)] {
            list.append(ClearAllLocalData.defaults(name: name, store: store, keys: allKeys,
                prefixes: ClearAllDataKeys.standardPrefixes, validateWriterGate: validateResetGate))
        }
        for (name, url) in [("recipe-shopping-sync-commit", paths.commitDirectory),
                            ("legacy-recipe-shopping-preservation", paths.legacyPreservationDirectory),
                            ("recipe-store-backups", paths.recipeBackupDirectory), ("journal-store-backups", paths.journalBackupDirectory),
                            ("shared-inbox-files", paths.sharedInboxDirectory), ("shared-cover-files", paths.sharedCoverDirectory),
                            ("app-only-cover-files", paths.appOnlyCoverDirectory)] {
            list.append(ClearAllLocalData.directory(name: name, url: url, validateWriterGate: validateResetGate))
        }
        list.append(Self.selectedEntries(name: "recovered-recipe-exports", directory: paths.recoveredExportDirectory,
            selected: { $0.hasPrefix("Ate-recovered-") && $0.hasSuffix(".json") }, validateResetGate: validateResetGate))
        list.append(Self.selectedEntries(name: "temporary-personal-exports", directory: paths.temporaryExportDirectory,
            selected: { ["ate-data.json", "ate-shopping-list.txt", "ate-shopping-list.csv"].contains($0)
                || $0.hasPrefix("ate-beta-") || $0.hasPrefix("ate-diagnostics-") }, validateResetGate: validateResetGate))
        // Archive transaction directories contain raw before/after images. Leave
        // minimal epoch/generation/lock control, erase even malformed txn evidence.
        list.append(Self.selectedEntries(name: "archive-personal-transactions", directory: paths.archiveControlDirectory,
            selected: { $0.hasPrefix("txn-") }, validateResetGate: validateResetGate))
        list.append(Self.selectedEntries(name: "qa-mock-server-cache", directory: paths.cacheDirectory,
            selected: { $0 == "qa-mock-server.json" }, validateResetGate: validateResetGate))
        let required = journalRequired.union(Self.ownNames)
        guard Set(list.map(\.name)).count == list.count, Set(list.map(\.name)) == required else { throw ClearAllLocalData.Error.missingRequiredComponent }
        return (list, required)
    }
    /// Trusted root plus app-owned filename conventions only. No paths from records.
    /// Child symlinks are unlinked, never followed; unrelated sibling files remain.
    static func selectedEntries(name: String, directory: URL, selected: @escaping (String) -> Bool,
                                validateResetGate: @escaping () throws -> Void) -> ClearAllLocalData.Component {
        func entries() throws -> [URL] {
            guard directory.isFileURL, directory.path != "/", directory.standardizedFileURL == directory,
                  directory.resolvingSymlinksInPath().standardizedFileURL == directory else { throw Refusal.unsafePath }
            var st = stat()
            guard lstat(directory.path, &st) == 0 else {
                if errno == ENOENT { return [] }
                throw Refusal.unsafePath
            }
            guard (st.st_mode & S_IFMT) == S_IFDIR else { throw Refusal.unsafePath }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { selected($0.lastPathComponent) }
        }
        return .init(name: name, erase: {
            for url in try entries() { try validateResetGate(); try FileManager.default.removeItem(at: url) }
        }, verifyEmpty: {
            guard try entries().isEmpty else { throw ClearAllLocalData.Error.notEmpty }
        })
    }
}
