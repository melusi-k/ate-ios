import Foundation

/// Exact byte persistence only. Coordinator owns semantic control validation. The
/// real graph supplies shared-file persistence; UserDefaults is fixture compatibility.
protocol ResetControlPersistence {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func remove() throws
}

struct DefaultsResetControlPersistence: ResetControlPersistence {
    let defaults: UserDefaults
    let key: String
    func read() throws -> Data? {
        guard defaults.object(forKey: key) != nil else { return nil }
        guard let bytes = defaults.data(forKey: key) else { throw ClearAllControlError.corruptRecord }
        return bytes
    }
    func write(_ data: Data) throws {
        defaults.set(data, forKey: key)
        guard try read() == data else { throw ClearAllControlError.persistenceUnverified }
    }
    func remove() throws {
        defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else { throw ClearAllControlError.persistenceUnverified }
    }
}
