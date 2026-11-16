import Foundation

/// Session-local priority, shared by both real URL delivery paths through
/// AppStore.handle(url:). Incoming work never marks a tour seen.
struct ProductUpdatesIncomingWork {
    private(set) var received = false
    var tourPresented = false
    private var pendingURLs: [URL] = []

    mutating func receive(_ url: URL) -> Bool {
        received = true
        guard tourPresented else { return true }
        pendingURLs.append(url)
        return false
    }
    mutating func finishTour() -> [URL] {
        tourPresented = false
        defer { pendingURLs = [] }
        return pendingURLs
    }
}
