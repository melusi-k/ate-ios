import Foundation
import SwiftData

/// Local erasure primitive only. No call sites. Not an account/cloud deletion API.
/// Caller must quiesce sync, generators, intents, widgets and store writers FIRST.
/// Keep that gate held until every component verifies empty, including retries.
/// Erasure is intentionally NOT backed up for rollback: a retained backup is user data.
@MainActor
enum ClearAllLocalData {
    struct Failure: Equatable { let component: String; let operation: String; let detail: String }
    struct Report {
        let verifiedEmpty: [String]
        let failures: [Failure]
        var complete: Bool { failures.isEmpty }
    }
    struct Component {
        let name: String
        let erase: () throws -> Void
        let verifyEmpty: () throws -> Void
    }
    enum Error: Swift.Error { case duplicateComponent, missingRequiredComponent, notEmpty, unavailableStore, unsafeDirectory }

    /// Never short-circuit after one failed store and never turn partial success into
    /// "All data cleared". Each component must independently prove empty.
    static func execute(_ components: [Component], requiredNames: Set<String>,
                        validateWriterGate: () throws -> Void) throws -> Report {
        let names = components.map(\.name)
        guard Set(names).count == names.count else { throw Error.duplicateComponent }
        guard !requiredNames.isEmpty, Set(names) == requiredNames else { throw Error.missingRequiredComponent }
        try validateWriterGate()
        var empty: [String] = []; var failures: [Failure] = []
        for component in components {
            do {
                try validateWriterGate()
                try component.erase()
            } catch {
                failures.append(Failure(component: component.name, operation: "erase", detail: String(describing: error)))
                continue
            }
            do {
                try validateWriterGate()
                try component.verifyEmpty()
                empty.append(component.name)
            } catch {
                failures.append(Failure(component: component.name, operation: "verify", detail: String(describing: error)))
            }
        }
        do { try validateWriterGate() }
        catch { failures.append(Failure(component: "writer-gate", operation: "final-verify", detail: String(describing: error))) }
        return Report(verifiedEmpty: empty, failures: failures)
    }

    static func recipesAndShopping(container: ModelContainer?,
                                   validateWriterGate: @escaping () throws -> Void,
                                   save: @escaping (ModelContext) throws -> Void = { try $0.save() }) -> Component {
        Component(name: "recipes-shopping", erase: {
            guard let container else { throw Error.unavailableStore }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                try validateWriterGate()
                for row in try context.fetch(FetchDescriptor<RecipeEntity>()) { try validateWriterGate(); context.delete(row) }
                for row in try context.fetch(FetchDescriptor<ShoppingEntity>()) { try validateWriterGate(); context.delete(row) }
                try validateWriterGate(); try save(context)
            } catch { context.rollback(); throw error }
        }, verifyEmpty: {
            guard let container else { throw Error.unavailableStore }
            let fresh = ModelContext(container)
            guard try fresh.fetch(FetchDescriptor<RecipeEntity>()).isEmpty,
                  try fresh.fetch(FetchDescriptor<ShoppingEntity>()).isEmpty else { throw Error.notEmpty }
        })
    }

    static func journal(container: ModelContainer?,
                        validateWriterGate: @escaping () throws -> Void,
                        save: @escaping (ModelContext) throws -> Void = { try $0.save() }) -> Component {
        Component(name: "journal-rows-payloads", erase: {
            guard let container else { throw Error.unavailableStore }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                // Fetch all payloads directly: clear includes orphan/invalid/future rows.
                // Do not use entries()/readMeals(), whose filters could skip data.
                for row in try context.fetch(FetchDescriptor<JournalMealPayload>()) { try validateWriterGate(); context.delete(row) }
                for row in try context.fetch(FetchDescriptor<JournalEntry>()) { try validateWriterGate(); context.delete(row) }
                try validateWriterGate(); try save(context)
            } catch { context.rollback(); throw error }
        }, verifyEmpty: {
            guard let container else { throw Error.unavailableStore }
            let fresh = ModelContext(container)
            guard try fresh.fetch(FetchDescriptor<JournalEntry>()).isEmpty,
                  try fresh.fetch(FetchDescriptor<JournalMealPayload>()).isEmpty else { throw Error.notEmpty }
        })
    }

    /// An explicit app-owned allowlist, not removePersistentDomain or a blanket
    /// ate.* match. Does NOT erase session/PKCE, subscriptions or OS permissions.
    static func defaults(name: String, store: UserDefaults, keys: Set<String>,
                         prefixes: [String] = [], validateWriterGate: @escaping () throws -> Void) -> Component {
        func selectedKeys() -> Set<String> {
            keys.union(store.dictionaryRepresentation().keys.filter { key in prefixes.contains { key.hasPrefix($0) } })
        }
        return Component(name: name, erase: {
            for key in selectedKeys() { try validateWriterGate(); store.removeObject(forKey: key) }
        }, verifyEmpty: {
            guard selectedKeys().allSatisfy({ store.object(forKey: $0) == nil }) else { throw Error.notEmpty }
        })
    }

    static func nutritionGoals(storage: NutritionGoalsStorage,
                               validateWriterGate: @escaping () throws -> Void) -> Component {
        Component(name: "nutrition-goals-file", erase: {
            try validateWriterGate(); try storage.remove()
        }, verifyEmpty: {
            guard try storage.read() == nil else { throw Error.notEmpty }
        })
    }

    /// Explicitly supplied trusted app-owned directory only; no filenames from rows
    /// are joined to a path. Reject link root/ancestor, unlink child links themselves.
    /// Caller must serialize all processes; no hostile same-UID race-safety claim.
    /// Clears all children, including orphan media, not only referenced filenames.
    static func directory(name: String, url: URL,
                          validateWriterGate: @escaping () throws -> Void,
                          fileManager fm: FileManager = .default) -> Component {
        func validateRoot() throws -> Bool {
            guard url.isFileURL, url.path.hasPrefix("/"), url.path != "/" else { throw Error.unsafeDirectory }
            var cursor = URL(fileURLWithPath: "/", isDirectory: true)
            for part in url.path.split(separator: "/") {
                guard part != ".", part != ".." else { throw Error.unsafeDirectory }
                cursor.appendPathComponent(String(part), isDirectory: true)
                do {
                    let attrs = try fm.attributesOfItem(atPath: cursor.path)
                    guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw Error.unsafeDirectory }
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return false }
            }
            return true
        }
        return Component(name: name, erase: {
            guard try validateRoot() else { return }
            for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try validateWriterGate()
                // Foundation removal of a symbolic link removes that link, not its target.
                try fm.removeItem(at: child)
            }
        }, verifyEmpty: {
            guard try validateRoot() else { return }
            guard try fm.contentsOfDirectory(atPath: url.path).isEmpty else { throw Error.notEmpty }
        })
    }
}
