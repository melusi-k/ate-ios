import Foundation

/// Hand-off queue from the "Save to ate" share extension to the app (stored in the App Group).
enum SharedInbox {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var url: String?
        var text: String?
        /// File name inside the App Group container's `Inbox/` folder.
        var imageFile: String?
        var date = Date()
    }

    static let key = "ate.inbox.v1"

    static func load(_ d: UserDefaults = SharedContainer.defaults) -> [Item] {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? []
    }
    static func save(_ items: [Item], _ d: UserDefaults = SharedContainer.defaults) {
        d.set(try? JSONEncoder().encode(items), forKey: key)
    }
    static func push(_ item: Item, _ d: UserDefaults = SharedContainer.defaults) {
        var all = load(d); all.append(item); save(Array(all.suffix(20)), d)
    }
    /// Removes and returns the oldest item.
    static func pop(_ d: UserDefaults = SharedContainer.defaults) -> Item? {
        var all = load(d)
        guard !all.isEmpty else { return nil }
        let first = all.removeFirst(); save(all, d); return first
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedContainer.groupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }
    /// Resolve only the UUID-named JPEG files produced by the share extension.
    /// Inbox metadata is persisted in a shared container, so never trust a stored path.
    static func safeImageURL(_ filename: String, in directory: URL) -> URL? {
        guard filename.hasSuffix(".jpg"),
              let id = UUID(uuidString: String(filename.dropLast(4))),
              id.uuidString.caseInsensitiveCompare(String(filename.dropLast(4))) == .orderedSame else { return nil }
        let root = directory.standardizedFileURL
        let candidate = root.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else { return nil }
        return candidate
    }

    static func imageData(_ item: Item) -> Data? {
        guard let f = item.imageFile, let dir = folder, let u = safeImageURL(f, in: dir) else { return nil }
        defer { try? FileManager.default.removeItem(at: u) }
        return try? Data(contentsOf: u)
    }

    /// First http(s) URL in free text (e.g. a TikTok caption shared as text).
    static func firstURL(in text: String) -> String? {
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let m = det?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        guard let u = m?.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return nil }
        return u.absoluteString
    }
}
