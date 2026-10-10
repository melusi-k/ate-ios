import Foundation

/// Share-link building and parsing.
/// Outgoing: `ATE_SHARE_URL_TEMPLATE` with `{slug}` (default GitHub Pages `…/ate-legal/r/?s={slug}`, which answers 200;
/// the `/r/<slug>` path form 404s before its JS redirect, so it is never produced).
/// Incoming: `ate://recipe/<slug>`, `ate://r/<slug>`, `<any host>/r/<slug>`, `<any host>/recipe/<slug>`,
/// `<host>/…/r/?s=<slug>` (and `?slug=`).
enum ShareLinks {
    static let defaultTemplate = "https://melusi-k.github.io/ate-legal/r/?s={slug}"

    static func url(slug: String, template: String = defaultTemplate) -> String {
        let t = template.contains("{slug}") ? template : defaultTemplate
        let s = slug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?/#"))) ?? slug
        return t.replacingOccurrences(of: "{slug}", with: s)
    }

    static func slug(from url: URL) -> String? {
        if url.scheme == "ate" {
            let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
            if let f = parts.first, f == "recipe" || f == "r", parts.count > 1 { return parts[1] }
            return nil
        }
        let comps = url.pathComponents.filter { $0 != "/" }
        if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let s = q.first(where: { $0.name == "s" || $0.name == "slug" })?.value, !s.isEmpty,
           comps.contains("r") || comps.contains("recipe") { return s }
        if let i = comps.firstIndex(where: { $0 == "r" || $0 == "recipe" }), i + 1 < comps.count, !comps[i + 1].isEmpty { return comps[i + 1] }
        return nil
    }
}
