import Foundation

/// A-CREATE-05: survives the app being killed mid-generation. `pending` is written when a generation starts and
/// cleared when it ends; `draft` holds a generated-but-unsaved card until it's saved or the sheet is dismissed.
final class DraftStore {
    struct Pending: Codable, Equatable { var mode: String; var text: String; var startedAt: Double; var imageData: Data? = nil }
    static let shared = DraftStore(defaults: .standard,
                                   enabled: !AppConfig.isUITesting || ProcessInfo.processInfo.arguments.contains("-qaPersistDraft"))
    private let d: UserDefaults
    private let enabled: Bool
    private let writerBoundary: FoodJournalWriterBoundary
    private let pKey = "ate.draft.pending.v1", dKey = "ate.draft.card.v1"
    init(defaults: UserDefaults, enabled: Bool, writerBoundary: FoodJournalWriterBoundary = .legacy) {
        d = defaults; self.enabled = enabled; self.writerBoundary = writerBoundary
        if ProcessInfo.processInfo.arguments.contains("-qaResetDraft") { clear() }
    }
    var pending: Pending? { enabled ? d.data(forKey: pKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } : nil }
    var draft: RecipeCard? { enabled ? d.data(forKey: dKey).flatMap { try? JSONDecoder().decode(RecipeCard.self, from: $0) } : nil }
    @discardableResult
    func begin(mode: String, text: String, imageData: Data? = nil) -> Bool {
        // Deliberately disabled persistence (hermetic UI tests) accepts a no-op.
        guard enabled else { return true }
        // Persist a bounded, downsampled photo with the pending request so Retry can reconstruct image input after relaunch.
        let recoverableImage = imageData.flatMap { $0.count <= 1_500_000 ? $0 : nil }
        return (try? writerBoundary.withEffect {
            let data = try JSONEncoder().encode(Pending(mode: mode, text: String(text.prefix(4000)), startedAt: Date().timeIntervalSince1970, imageData: recoverableImage))
            d.set(data, forKey: pKey)
        }) != nil
    }
    @discardableResult
    func end() -> Bool { (try? writerBoundary.withEffect { d.removeObject(forKey: pKey) }) != nil }
    @discardableResult
    func saveDraft(_ c: RecipeCard) -> Bool {
        // Deliberately disabled persistence (hermetic UI tests) accepts a no-op.
        guard enabled else { return true }
        return (try? writerBoundary.withEffect {
            let data = try JSONEncoder().encode(c) // encode before retiring recoverable input
            d.removeObject(forKey: pKey)
            d.set(data, forKey: dKey)
        }) != nil
    }
    @discardableResult
    func clear() -> Bool {
        (try? writerBoundary.withEffect { d.removeObject(forKey: pKey); d.removeObject(forKey: dKey) }) != nil
    }
}
