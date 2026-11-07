import Foundation

/// Durable record of a recipe linked to a Journal entry (#245). It keeps what the recipe was called and, when the
/// link comes from a completed cook, the local day it was cooked, so the entry stays understandable after the recipe
/// is edited or deleted. The CALLER captures these values at the moment it holds the right context (for a cooked
/// recipe, at Finish cooking); storage never recomputes them from the current recipe later.
struct JournalRecipeSnapshot: Codable, Equatable {
    var recipeID: String
    var title: String
    /// Local YYYY-MM-DD (the `CookingHistory.key(for:)` format) for a completed cook. nil means the link was NOT a
    /// cook (for example a suggested recipe); a reflection about a cooked recipe must supply the real day.
    var cookedDayKey: String?
}

/// What `JournalRecipeSnapshotCodec.decode` found. `undecodable` leaves the stored raw string untouched: reading
/// never rewrites it, so a newer build or a damaged value cannot be destroyed by this build.
enum JournalRecipeSnapshotDecoding: Equatable {
    case none
    case snapshots([JournalRecipeSnapshot])
    /// `reason` carries the underlying decoder detail (the `DecodingError` description) when there is one.
    case undecodable(reason: String)
}

/// Why `JournalEntry.setRecipeSnapshots` did not store anything. Neither case changes the stored raw value.
enum JournalRecipeSnapshotWriteError: Error, Equatable {
    /// The stored payload is damaged or written by another version. It is never overwritten by this build.
    case existingPayloadUndecodable(reason: String)
    /// JSON encoding of a non-empty list failed.
    case encodingFailed(String)
}

/// Versioned JSON codec stored in `JournalEntry.recipeSnapshotsRaw`.
enum JournalRecipeSnapshotCodec {
    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var snapshots: [JournalRecipeSnapshot]
    }

    /// nil only for an empty list (nothing to store). A failure to encode a non-empty list throws, so it can never
    /// be mistaken for "empty".
    static func encode(_ snapshots: [JournalRecipeSnapshot]) throws -> String? {
        guard !snapshots.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(Envelope(version: currentVersion, snapshots: snapshots))
            guard let text = String(data: data, encoding: .utf8) else {
                throw JournalRecipeSnapshotWriteError.encodingFailed("encoded data is not UTF-8")
            }
            return text
        } catch let error as JournalRecipeSnapshotWriteError {
            throw error
        } catch {
            throw JournalRecipeSnapshotWriteError.encodingFailed(String(describing: error))
        }
    }

    static func decode(_ raw: String?) -> JournalRecipeSnapshotDecoding {
        guard let raw, !raw.isEmpty else { return .none }
        guard let data = raw.data(using: .utf8) else { return .undecodable(reason: "not UTF-8") }
        struct VersionOnly: Decodable { var version: Int }
        let version: Int
        do {
            version = try JSONDecoder().decode(VersionOnly.self, from: data).version
        } catch {
            return .undecodable(reason: "no readable version: \(String(describing: error))")
        }
        guard version == currentVersion else { return .undecodable(reason: "unsupported version \(version)") }
        do {
            return .snapshots(try JSONDecoder().decode(Envelope.self, from: data).snapshots)
        } catch {
            return .undecodable(reason: "version \(version) payload does not match its shape: \(String(describing: error))")
        }
    }
}
