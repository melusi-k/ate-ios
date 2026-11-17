import Foundation
import CoreFoundation

/// Explicit payload compatibility boundary. Legacy unversioned rows remain version 0.
/// Version 1 is the current domain shape plus one schemaVersion field. Unknown or
/// ambiguous declarations are refused before any account cleanup/merge/persistence.
/// This does not enable versioned writes; a later schema rollout owns that transition.
enum SyncPayloadVersion {
    static let current = 1

    static func compatibleFields(_ raw: Data) -> [String: Any]? {
        guard let fields = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              fields["schema_version"] == nil else { return nil }
        if let version = fields["schemaVersion"] {
            // NSNumber bridges Bool as a number; inspect its JSON type before accepting 1.
            guard let number = version as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(current) else { return nil }
        }
        return fields
    }
}
