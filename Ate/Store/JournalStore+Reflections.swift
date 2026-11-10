import Foundation
import SwiftData

/// Reflection-only consumers must never treat structured meals as empty reflections or infer
/// a Health state from their legacy computed-state fallback. The unified timeline stays all-kind.
extension JournalStore {
    func readReflections() throws -> [JournalEntry] {
        guard let container else { throw JournalTimelineReadError.storeUnavailable }
        // Do not reuse retained main-context rows after an isolated edit or deletion.
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let rows: [JournalEntry]
        do { rows = try context.fetch(FetchDescriptor<JournalEntry>()) }
        catch { throw JournalTimelineReadError.readFailed }
        return rows.filter { $0.kindRaw == JournalEntryKind.reflection.rawValue }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
}
