import Foundation

/// A-CREATE-05: survives the app being killed mid-generation. `pending` is written when a generation starts and
/// cleared when it ends; `draft` holds a generated-but-unsaved card until it's saved or the sheet is dismissed.
final class DraftStore {
    struct Pending: Codable, Equatable { var mode: String; var text: String; var startedAt: Double }
    static let shared = DraftStore(defaults: .standard,
                                   enabled: !AppConfig.isUITesting || ProcessInfo.processInfo.arguments.contains("-qaPersistDraft"))
    private let d: UserDefaults
    private let enabled: Bool
    private let pKey = "ate.draft.pending.v1", dKey = "ate.draft.card.v1"
    init(defaults: UserDefaults, enabled: Bool) {
        d = defaults; self.enabled = enabled
        if ProcessInfo.processInfo.arguments.contains("-qaResetDraft") { clear() }
    }
    var pending: Pending? { enabled ? d.data(forKey: pKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } : nil }
    var draft: RecipeCard? { enabled ? d.data(forKey: dKey).flatMap { try? JSONDecoder().decode(RecipeCard.self, from: $0) } : nil }
    func begin(mode: String, text: String) {
        guard enabled else { return }
        d.set(try? JSONEncoder().encode(Pending(mode: mode, text: String(text.prefix(4000)), startedAt: Date().timeIntervalSince1970)), forKey: pKey)
    }
    func end() { d.removeObject(forKey: pKey) }
    func saveDraft(_ c: RecipeCard) { guard enabled else { return }; end(); d.set(try? JSONEncoder().encode(c), forKey: dKey) }
    func clear() { d.removeObject(forKey: pKey); d.removeObject(forKey: dKey) }
}
