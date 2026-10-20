import Foundation
import SwiftData
import os

/// SwiftData corruption recovery (R-DATA-01). Opening the store never crashes the app:
/// 1. open normally; 2. on failure move the store files aside to Backups/ate-<timestamp>.store*, open a fresh store;
/// 3. if that fails too, fall back to an in-memory store (and finally to no store; AppStore works without a context).
/// After launch, AppStore restores from Supabase sync when signed in and writes a JSON export of what it recovered.
enum StoreRecovery {
    static let log = Logger(subsystem: "com.melusik.ate", category: "store")

    struct Outcome {
        var container: ModelContainer?
        var recovered = false          // a broken store was moved aside
        var inMemoryFallback = false
        var backupURL: URL?
        var error: String?
    }

    static var defaultStoreURL: URL { ModelConfiguration().url }

    static func open(url: URL? = nil, inMemory: Bool = false, now: Date = Date(),
                     make: (ModelConfiguration) throws -> ModelContainer = { try ModelContainer(for: RecipeEntity.self, ShoppingEntity.self, configurations: $0) })
        -> Outcome {
        if inMemory {
            return Outcome(container: try? make(ModelConfiguration(isStoredInMemoryOnly: true)))
        }
        let storeURL = url ?? defaultStoreURL
        let config = ModelConfiguration(url: storeURL)
        do { return Outcome(container: try make(config)) } catch {
            DiagnosticHistory.shared.record(.storeOpenFailed)
            log.error("Store open failed: \(error.localizedDescription, privacy: .public)")
            var out = Outcome(error: error.localizedDescription)
            out.backupURL = moveAside(storeURL, now: now)
            out.recovered = out.backupURL != nil
            if let c = try? make(ModelConfiguration(url: storeURL)) {
                out.container = c
                if out.recovered { DiagnosticHistory.shared.record(.storeRecovered) }
                return out
            }
            out.container = try? make(ModelConfiguration(isStoredInMemoryOnly: true))
            out.inMemoryFallback = out.container != nil
            if out.inMemoryFallback { DiagnosticHistory.shared.record(.storeInMemoryFallback) }
            return out
        }
    }

    /// Moves `x.store`, `x.store-wal`, `x.store-shm` into a sibling Backups folder. Returns the main backup file.
    static func moveAside(_ storeURL: URL, now: Date = Date(), fm: FileManager = .default) -> URL? {
        let dir = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let stamp = f.string(from: now)
        var main: URL?
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("ate-\(stamp).\(storeURL.pathExtension.isEmpty ? "store" : storeURL.pathExtension)\(suffix)")
            try? fm.removeItem(at: dst)
            do { try fm.moveItem(at: src, to: dst); if suffix.isEmpty { main = dst } }
            catch { log.error("Backup move failed: \(error.localizedDescription, privacy: .public)") }
        }
        return main
    }

    /// JSON export of recipes recovered after a repair (Documents/Ate-recovered-<timestamp>.json).
    @discardableResult
    static func exportRecovered(_ recipes: [RecipeCard], now: Date = Date(), dir: URL? = nil) -> URL? {
        let base = dir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let url = base.appendingPathComponent("Ate-recovered-\(f.string(from: now)).json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(recipes), (try? d.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}

/// Every context.save() goes through here: retry, log, report (R-DATA-02).
@MainActor
enum StoreSaver {
    /// Tests inject a failure here.
    static var injectFailure: (() throws -> Void)?
    static var onFailure: ((String) -> Void)?
    private(set) static var failures = 0

    @discardableResult
    static func save(_ context: ModelContext, what: String, retries: Int = 2) -> Bool {
        var last: Error?
        for attempt in 0...retries {
            do {
                try injectFailure?()
                try context.save()
                return true
            } catch {
                last = error
                StoreRecovery.log.error("Save \(what, privacy: .public) failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                if attempt < retries { context.processPendingChanges() }
            }
        }
        failures += 1
        DiagnosticHistory.shared.record(.saveFailed)
        onFailure?("Couldn't save your \(what) on this iPhone. Ate will keep trying; your changes are still on screen\(last == nil ? "" : ".")")
        return false
    }
    static func resetForTests() { failures = 0; injectFailure = nil; onFailure = nil }
}
