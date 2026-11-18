import Foundation

struct CookedDayNote: Identifiable, Equatable {
    let id: String
    let recipeID: String
    let text: String
}

/// A fresh read of existing reflection rows, not a retained copy of deleted notes.
/// Cooking alone and recipe suggestions never create a reflection or an eaten meal.
enum CookedDayNotes {
    @MainActor static func read(dayKey: String, recipeIDs: Set<String>, journal: JournalStore) throws -> [CookedDayNote] {
        var result: [CookedDayNote] = []
        for entry in try journal.readReflections() {
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            switch entry.recipeSnapshotDecoding {
            case .none: continue
            case .undecodable: throw JournalReadError.readFailed
            case .snapshots(let snapshots):
                var seen = Set<String>()
                for snapshot in snapshots where snapshot.cookedDayKey == dayKey && recipeIDs.contains(snapshot.recipeID) {
                    guard seen.insert(snapshot.recipeID).inserted else { continue }
                    result.append(CookedDayNote(id: entry.id + ":" + snapshot.recipeID, recipeID: snapshot.recipeID, text: entry.text))
                }
            }
        }
        return result
    }
}
