import Foundation
import SwiftData

enum JournalTimelineReadError: Error, Equatable {
    /// The journal container is not available (store failed to open).
    case storeUnavailable
    /// A fetch from the store failed. The timeline must show this honestly, never an empty journal.
    case readFailed
}

extension FoodJournalStore {
    /// Read-only snapshot of every journal entry as timeline rows (#245 step 4 prep).
    ///
    /// One row per stored `JournalEntry`, meals and reflections alike. Nothing is dropped: a meal row whose payload is
    /// missing stays in the list (`meal` is nil), and a reflection written before #245 (no day key) falls back to the
    /// local day of its `createdAt`. The method never inserts, edits or saves, so reading the timeline cannot change the
    /// store. An unavailable store or a failed fetch throws instead of returning an empty list, so a read error is never
    /// shown as "no entries".
    func timelineItems(calendar: Calendar = .autoupdatingCurrent) throws -> [JournalTimelineItem] {
        guard let ctx = container?.mainContext else { throw JournalTimelineReadError.storeUnavailable }
        let entries: [JournalEntry]
        let payloads: [JournalMealPayload]
        do {
            entries = try ctx.fetch(FetchDescriptor<JournalEntry>())
            payloads = try ctx.fetch(FetchDescriptor<JournalMealPayload>())
        } catch {
            throw JournalTimelineReadError.readFailed
        }
        let payloadByEntry = Dictionary(payloads.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.map { entry in
            JournalTimeline.item(from: entry, payload: payloadByEntry[entry.id], calendar: calendar)
        }
    }
}
