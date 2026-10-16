import Foundation

enum ClipRecipeLink {
    static func slug(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        let querySlug = components.queryItems?.first(where: { $0.name == "s" || $0.name == "slug" })?.value
        let hasRecipePath = path.contains("r") || path.contains("recipe")
        let candidate: String?
        if hasRecipePath, let querySlug { candidate = querySlug }
        else if let index = path.firstIndex(where: { $0 == "r" || $0 == "recipe" }), path.indices.contains(index + 1) { candidate = path[index + 1] }
        else { candidate = nil }
        guard let candidate, candidate.range(of: "^[a-zA-Z0-9]{4,40}$", options: .regularExpression) != nil else { return nil }
        return candidate
    }
}
