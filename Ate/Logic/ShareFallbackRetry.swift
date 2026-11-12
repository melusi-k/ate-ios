import Foundation

/// A retry may start only after the fallback presentation has actually dismissed.
/// In particular, a synchronously failing publisher must not present its error
/// while SwiftUI is still dismissing the previous error presentation.
struct ShareFallbackRetry {
    enum Action { case retry(RecipeCard), text(RecipeCard) }
    private var pending: Action?
    mutating func request(_ recipe: RecipeCard) { pending = .retry(recipe) }
    mutating func requestText(_ recipe: RecipeCard) { pending = .text(recipe) }
    mutating func presentationDidDismiss() -> Action? {
        defer { pending = nil }
        return pending
    }
}
