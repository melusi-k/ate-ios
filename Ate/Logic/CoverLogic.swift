import Foundation

/// Pure, testable rules for recipe cover images (no UIKit).
enum CoverLogic {
    /// Where a cover came from, in priority order (lower rawValue wins).
    enum Source: Int, Comparable, CaseIterable {
        case userPhoto = 0, pageImage = 1, generated = 2, tile = 3
        static func < (a: Source, b: Source) -> Bool { a.rawValue < b.rawValue }
    }

    /// Candidate covers available for a recipe → the one to show.
    static func pick(userPhoto: Bool, pageImage: Bool, generated: Bool) -> Source {
        if userPhoto { return .userPhoto }
        if pageImage { return .pageImage }
        if generated { return .generated }
        return .tile
    }

    /// Stored file name for a recipe's cover (local, never synced as bytes).
    static func fileName(for recipeID: String, source: Source) -> String {
        let safe = recipeID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "cover-\(safe)-\(source.rawValue).jpg"
    }
    /// Source encoded in a stored file name (nil for unknown names).
    static func source(ofFile name: String?) -> Source? {
        guard let n = name, n.hasPrefix("cover-"), n.hasSuffix(".jpg") else { return nil }
        let core = n.dropLast(4)
        guard let last = core.split(separator: "-").last, let raw = Int(last) else { return nil }
        return Source(rawValue: raw)
    }

    /// Only https images are fetched, stored remotely, or shared.
    static func httpsURL(_ s: String?) -> URL? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let u = URL(string: s), u.scheme?.lowercased() == "https", u.host?.isEmpty == false else { return nil }
        return u
    }

    // MARK: page image parsing

    /// Best cover image in an HTML page: og:image(:secure_url) → twitter:image → JSON-LD Recipe image → link rel=image_src.
    static func pageImage(fromHTML html: String, baseURL: URL? = nil) -> URL? {
        let meta = SocialLinks.meta(html)
        let keys = ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"]
        var candidates = keys.compactMap { meta[$0] }
        if let card = JSONLD.recipe(fromHTML: html, sourceURL: nil), let i = card.imageURL { candidates.append(i) }
        if let r = try? NSRegularExpression(pattern: #"<link[^>]+rel=["']image_src["'][^>]+href=["']([^"']+)["']"#, options: .caseInsensitive),
           let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let g = Range(m.range(at: 1), in: html) {
            candidates.append(String(html[g]))
        }
        for c in candidates {
            let s = SocialLinks.decodeEntities(c).trimmingCharacters(in: .whitespaces)
            let abs = URL(string: s, relativeTo: baseURL)?.absoluteURL
            if let u = httpsURL(abs?.absoluteString) { return u }
        }
        return nil
    }

    /// `thumbnail_url` from an oEmbed JSON response (YouTube/TikTok/Instagram).
    static func oEmbedThumbnail(_ json: [String: Any]?) -> URL? {
        httpsURL(json?["thumbnail_url"] as? String)
    }

    // MARK: branded tile

    struct Tile: Equatable {
        /// Index into `palettes` (warm brand gradients).
        var palette: Int
        var initial: String
        var symbol: String
    }

    /// Warm brand gradients (hex pairs). No greens.
    static let palettes: [(UInt32, UInt32)] = [
        (0xF5E2C0, 0xE77140), // cream → ember
        (0xF3C79B, 0xB9481F), // apricot → rust
        (0xFBE3B4, 0xD9892B), // butter → saffron
        (0xF2C4A8, 0xA8432E), // peach → paprika
        (0xEFD6B8, 0x8A5A3C), // biscuit → cocoa
        (0xF7D2C4, 0xC25A4A), // blush → tomato
    ]

    /// Dish TYPE wins over protein ("chicken sandwich" is a sandwich, not a bird); rules are checked against the
    /// title first, then the first ingredients, with whole-word matching ("tea" must not match "teaspoon"/"steak").
    private static let symbolRules: [([String], String, Int)] = [
        (["coffee", "tea", "chai", "rooibos", "smoothie", "drink", "juice", "latte", "cocktail", "lemonade"], "cup.and.saucer", 4),
        (["cake", "cookie", "cookies", "dessert", "chocolate", "tart", "pudding", "malva", "koeksister", "brownie", "muffin", "pancake", "pancakes"], "birthday.cake", 5),
        (["sandwich", "burger", "wrap", "toastie", "sub", "bunny chow", "kota", "taco", "tacos", "hotdog", "vetkoek"], "takeoutbag.and.cup.and.straw", 4),
        (["soup", "stew", "curry", "potjie", "chakalaka", "casserole", "braise"], "frying.pan", 1),
        (["salad", "bowl", "slaw"], "carrot", 3),
        (["fish", "salmon", "tuna", "prawn", "prawns", "shrimp", "seafood", "hake", "snoek", "calamari"], "fish", 0),
        (["ribs", "beef", "lamb", "pork", "steak", "mince", "braai", "boerewors", "mogodu", "tripe", "nyama", "oxtail", "chops", "brisket", "sausage", "wors"], "flame", 1),
        (["chicken", "turkey", "duck", "amanqina", "wings", "drumsticks"], "bird", 2),
        (["bread", "ujeqe", "pap", "maize", "rice", "pasta", "noodle", "noodles", "pizza", "gnocchi", "risotto"], "fork.knife.circle", 4),
        (["spinach", "morogo", "cabbage", "vegetable", "vegetables", "tomato", "carrot", "bean", "beans", "mushroom", "mushrooms"], "carrot", 3),
        (["egg", "eggs", "omelette", "shakshuka"], "frying.pan", 2),
    ]

    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }
    static func matches(_ text: String, _ key: String) -> Bool {
        let l = text.lowercased()
        return key.contains(" ") ? l.contains(key) : words(l).contains(key)
    }

    /// Deterministic tile for a recipe: same title/cuisine/ingredients → same tile.
    static func tile(title: String, cuisine: String?, ingredients: [String]) -> Tile {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = t.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "A"
        for hay in [t, ingredients.prefix(4).joined(separator: " ")] {
            for (keys, symbol, pal) in symbolRules where keys.contains(where: { matches(hay, $0) }) {
                return Tile(palette: (pal + stableHash(cuisine ?? "")) % palettes.count, initial: initial, symbol: symbol)
            }
        }
        let h = stableHash((cuisine ?? "") + "|" + t.lowercased())
        return Tile(palette: h % palettes.count, initial: initial, symbol: "fork.knife")
    }

    /// FNV-1a; stable across launches (unlike `hashValue`).
    static func stableHash(_ s: String) -> Int {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h & 0x7FFFFFFF)
    }

    /// Image Playground concept text: title + up to 3 main ingredients.
    static func concept(title: String, ingredients: [String]) -> String {
        let main = ingredients.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(3)
        return main.isEmpty ? "\(title), plated food" : "\(title) with \(main.joined(separator: ", ")), plated food"
    }

    /// Crop rect (in pixels) for a centered 4:3 crop.
    static func crop43(width w: Double, height h: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        let target = 4.0 / 3.0
        if w / h > target { let nw = h * target; return ((w - nw) / 2, 0, nw, h) }
        let nh = w / target; return (0, (h - nh) / 2, w, nh)
    }
}
