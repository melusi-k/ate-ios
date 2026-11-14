#if DEBUG
import Foundation
import UIKit
import OSLog

/// Synthetic saved preconditions only. No sort/group choices, favourites, shopping actions
/// or reorder results are seeded. Every native interaction and original assertion remains.
enum DogfoodSavedRecipeQAFixtures {
    @MainActor static func prepare(_ store: AppStore) {
        guard AppConfig.isUITesting else { return }
        let args = ProcessInfo.processInfo.arguments
        let menus = args.contains("-qaSavedRecipesForGroupSort")
        let apple = args.contains("-qaSavedAppleForGroup")
        let favourite = args.contains("-qaSavedRecipesForFavourite")
        let context = args.contains("-qaSavedZestyForContext")
        let reorder = args.contains("-qaSavedRecipesForDogfoodReorder")
        guard menus || apple || favourite || context || reorder else { return }
        precondition([menus, apple, favourite, context, reorder].filter { $0 }.count == 1)
        startAnimationDiagnostics()
        store.filter.clear()
        store.layout = LibraryLayout()
        let now = Date().timeIntervalSince1970 * 1000
        if apple || context {
            store.recipes = [card(id: "qa-dogfood-single", title: apple ? "Apple crumble" : "Zesty tacos", createdAt: now)]
        } else {
            let first = card(id: "qa-dogfood-first", title: reorder ? "First dish" : (favourite ? "Apple crumble" : "Zesty tacos"), createdAt: now - 1000)
            let second = card(id: "qa-dogfood-second", title: reorder ? "Second dish" : (favourite ? "Zesty tacos" : "Apple crumble"), createdAt: now)
            store.recipes = [second, first]
        }
    }

    @MainActor private static var diagnosticsStarted = false
    private static let animationLogger = Logger(subsystem: "com.melusik.ate", category: "LibraryMenuAnimationDiagnostic")

    /// Nine read-only samples, only in the explicit Library saved fixtures. No test waits,
    /// synchronization changes, menu actions, animation cancellation or cover mutation.
    @MainActor private static func startAnimationDiagnostics() {
        guard !diagnosticsStarted else { return }
        diagnosticsStarted = true
        Task { @MainActor in
            let started = ProcessInfo.processInfo.systemUptime
            for offset in [15.0, 30, 45, 60, 90, 120, 150, 180, 210] {
                let remaining = offset - (ProcessInfo.processInfo.systemUptime - started)
                if remaining > 0 {
                    do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                recordAnimations(offset: offset)
            }
        }
    }

    @MainActor private static func recordAnimations(offset: Double) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).prefix(8)
        var visited = 0, observed = 0, emitted = 0
        func inspect(_ layer: CALayer, depth: Int) {
            guard visited < 2048, depth < 64 else { return }
            visited += 1
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key) else { continue }
                observed += 1
                guard emitted < 64 else { continue }
                emitted += 1
                // Only animation structure and numeric timing. No view labels, recipe IDs,
                // layer names, file paths, model values or content from the animation.
                let kind = String(describing: type(of: animation))
                animationLogger.notice("sample=\(offset, privacy: .public) layerIndex=\(visited, privacy: .public) depth=\(depth, privacy: .public) type=\(kind, privacy: .public) duration=\(animation.duration, privacy: .public) repeatCount=\(animation.repeatCount, privacy: .public) repeatDuration=\(animation.repeatDuration, privacy: .public) speed=\(animation.speed, privacy: .public)")
            }
            for child in layer.sublayers ?? [] { inspect(child, depth: depth + 1) }
        }
        for window in windows { inspect(window.layer, depth: 0) }
        animationLogger.notice("sample=\(offset, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) windows=\(windows.count, privacy: .public) visited=\(visited, privacy: .public) observed=\(observed, privacy: .public) emitted=\(emitted, privacy: .public) coversLoading=\(CoverStore.shared.loading.count, privacy: .public)")
        // No animations observed does not prove all UIKit/SwiftUI animation bookkeeping idle.
        // System-process animations and framework completion tokens are outside this scan.
    }

    private static func card(id: String, title: String, createdAt: Double) -> RecipeCard {
        // Match the existing mock generation's 25-minute card, including shopping
        // ingredients, while keeping both recipes unordered and unfavourited.
        RecipeCard(id: id, title: title, servings: 2, timeMinutes: 25,
            ingredients: [.init(name: "salmon fillets", quantity: 2, unit: "pcs"),
                          .init(name: "white miso", quantity: 2, unit: "tbsp"),
                          .init(name: "honey", quantity: 1, unit: "tbsp"),
                          .init(name: "garlic", quantity: 2, unit: "cloves", notes: "finely chopped"),
                          .init(name: "rice", quantity: 150, unit: "g")],
            steps: [Step(order: 1, instruction: "Heat the oven to 200°C and line a tray.", timeSeconds: nil),
                    Step(order: 2, instruction: "Mix miso, honey and garlic; brush over the salmon.", timeSeconds: nil),
                    Step(order: 3, instruction: "Roast the salmon until just flaky.", timeSeconds: 600),
                    Step(order: 4, instruction: "Rest for a minute, then serve over rice.", timeSeconds: 60)],
            createdAt: createdAt)
    }
}
#endif
