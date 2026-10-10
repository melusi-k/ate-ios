import Foundation

/// Instagram / TikTok / YouTube links: these block normal page fetches, so we read oEmbed + OpenGraph metadata
/// (the caption usually lives in og:description) instead of the full page.
enum SocialLinks {
    enum Platform: String { case instagram = "Instagram", tiktok = "TikTok", youtube = "YouTube" }

    static func platform(of url: URL) -> Platform? {
        var h = (url.host ?? "").lowercased()
        for p in ["www.", "m.", "vm.", "vt."] where h.hasPrefix(p) { h.removeFirst(p.count) }
        if h == "instagram.com" || h.hasSuffix(".instagram.com") || h == "instagr.am" { return .instagram }
        if h == "tiktok.com" || h.hasSuffix(".tiktok.com") { return .tiktok }
        if h == "youtube.com" || h.hasSuffix(".youtube.com") || h == "youtu.be" { return .youtube }
        return nil
    }

    /// Query parameters that only track shares (dropped from every link we fetch or store).
    static let trackingParams: Set<String> = ["mdxt", "igsh", "igshid", "img_index", "utm_source", "utm_medium", "utm_campaign",
        "utm_term", "utm_content", "fbclid", "gclid", "si", "feature", "_r", "_t", "is_from_webapp", "sender_device", "share_app_id",
        "share_item_id", "share_link_id", "social_sharing", "source", "pp", "ab_channel"]

    /// Strips tracking params and fragments; for YouTube keeps only `v` (and `t`).
    static func clean(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let keep = (c.queryItems ?? []).filter { q in
            let n = q.name.lowercased()
            if platform(of: url) == .youtube { return n == "v" || n == "t" }
            return !trackingParams.contains(n) && !n.hasPrefix("utm_")
        }
        c.queryItems = keep.isEmpty ? nil : keep
        c.fragment = nil
        return c.url ?? url
    }

    static func oEmbedURL(for url: URL) -> URL? {
        let enc = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        switch platform(of: url) {
        case .tiktok: return URL(string: "https://www.tiktok.com/oembed?url=\(enc)")
        case .youtube: return URL(string: "https://www.youtube.com/oembed?format=json&url=\(enc)")
        case .instagram, nil: return nil   // Instagram oEmbed needs an app token
        }
    }

    /// `<meta property="og:…" content="…">` / `name="description"` values (attribute order-independent).
    static func meta(_ html: String) -> [String: String] {
        var out: [String: String] = [:]
        let tag = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive])
        let attr = try! NSRegularExpression(pattern: "(\\w[\\w:-]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')", options: [])
        let ns = html as NSString
        for m in tag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range) as NSString
            var a: [String: String] = [:]
            for am in attr.matches(in: t as String, range: NSRange(location: 0, length: t.length)) {
                let k = t.substring(with: am.range(at: 1)).lowercased()
                let r = am.range(at: 3).location != NSNotFound ? am.range(at: 3) : am.range(at: 4)
                a[k] = t.substring(with: r)
            }
            if let key = a["property"] ?? a["name"], let v = a["content"], out[key.lowercased()] == nil {
                out[key.lowercased()] = decodeEntities(v)
            }
        }
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        for (a, b) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#10;": "\n"] {
            r = r.replacingOccurrences(of: a, with: b)
        }
        // numeric entities (emoji etc.)
        let re = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for m in re.matches(in: r, range: NSRange(r.startIndex..., in: r)).reversed() {
            guard let whole = Range(m.range, in: r), let numR = Range(m.range(at: 2), in: r) else { continue }
            let hex = !(Range(m.range(at: 1), in: r).map { r[$0].isEmpty } ?? true)
            if let v = UInt32(r[numR], radix: hex ? 16 : 10), let u = Unicode.Scalar(v) { r.replaceSubrange(whole, with: String(Character(u))) }
        }
        return r
    }

    /// Caption text assembled from oEmbed JSON + OG tags. Instagram's og:description is
    /// `123 likes, 4 comments - user on May 1, 2024: "caption…"` — keep only the caption.
    static func caption(platform: Platform, oEmbed: [String: Any]?, meta: [String: String]) -> String {
        var parts: [String] = []
        if let t = oEmbed?["title"] as? String { parts.append(t) }
        let desc = meta["og:description"] ?? meta["description"]
        // Instagram: the caption (og:description minus "N likes, N comments - user on Date:") beats og:title ("Name on Instagram: …").
        if let t = meta["og:title"], !(platform == .instagram && desc != nil) {
            let tt = platform == .instagram ? CaptionAnalysis.stripInstagramPrefix(t) : t
            if !parts.contains(tt) { parts.append(tt) }
        }
        if var d = desc {
            if platform == .instagram { d = CaptionAnalysis.stripInstagramPrefix(d) }
            if !parts.contains(d) { parts.append(d) }
        }
        let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Generic login-wall copy is not a caption.
        let junk = ["Instagram", "Log in", "Sign up", "TikTok - Make Your Day", "YouTube", "Watch, follow, and discover"]
        if junk.contains(where: { joined == $0 || joined.hasPrefix($0 + " ") && joined.count < 60 }) { return "" }
        return joined
    }

    /// Enough text to plausibly contain a recipe (ingredients or steps)?
    static func isUseful(_ caption: String) -> Bool {
        let words = caption.split { $0.isWhitespace }.count
        return words >= 12
    }

    static func noCaptionMessage(_ p: Platform) -> String {
        "\(p.rawValue) didn't share the caption — paste the caption text into Prompt instead"
    }
}

/// Error the Add sheet can act on (one-tap switch to the Prompt tab).
struct SocialCaptionError: LocalizedError {
    let platform: SocialLinks.Platform
    var reason: String? = nil
    var errorDescription: String? { reason ?? SocialLinks.noCaptionMessage(platform) }
}
