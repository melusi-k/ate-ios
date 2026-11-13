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
    /// Appends an item (newest kept, 20 max) as one gated read-modify-write, so a
    /// share extension and the app can never lose each other's items. Returns false
    /// when the writer boundary refused the effect; nothing was queued and the
    /// caller must not claim the item was saved.
    @discardableResult
    static func push(_ item: Item, _ d: UserDefaults = SharedContainer.defaults,
                     boundary: SharedWriterBoundary = .current) -> Bool {
        (try? boundary.withEffect { () -> Void in
            var all = load(d); all.append(item); save(Array(all.suffix(20)), d)
        }) != nil
    }
    /// Image bytes and their queue reference publish under ONE original boundary.
    /// Capture the boundary before loading an asynchronous NSItemProvider; do not
    /// look up a fresh boundary/epoch after that await. No directory is created on
    /// a refused effect. This does not install the extension's production gate.
    @discardableResult
    static func pushImage(_ data: Data, item: Item,
                          directory: URL?, defaults: UserDefaults = SharedContainer.defaults,
                          boundary: SharedWriterBoundary) -> Bool {
        guard let directory else { return false }
        return (try? boundary.withEffect { () throws -> Void in
            let name = UUID().uuidString + ".jpg"
            guard let url = safeImageURL(name, in: directory) else { throw ImageFailure.unsafePath }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            var value = item; value.imageFile = name
            guard push(value, defaults, boundary: boundary) else { throw ImageFailure.queueFailed }
        }) != nil
    }
    private enum ImageFailure: Error { case unsafePath, queueFailed }

    /// Removes and returns the oldest item as one gated read-modify-write. A
    /// refused effect returns nil and leaves the inbox untouched.
    static func pop(_ d: UserDefaults = SharedContainer.defaults,
                    boundary: SharedWriterBoundary = .current) -> Item? {
        (try? boundary.withEffect { () -> Item? in
            var all = load(d)
            guard !all.isEmpty else { return nil }
            let first = all.removeFirst(); save(all, d); return first
        }) ?? nil
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

    static func imageData(_ item: Item, directory: URL? = folder, boundary: SharedWriterBoundary = .current) -> Data? {
        guard let f = item.imageFile, let dir = directory, let u = safeImageURL(f, in: dir) else { return nil }
        return (try? boundary.withEffect { () throws -> Data in
            let data = try Data(contentsOf: u)
            try FileManager.default.removeItem(at: u)
            return data
        })
    }

    /// First http(s) URL in free text (e.g. a TikTok caption shared as text).
    static func firstURL(in text: String) -> String? {
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let m = det?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        guard let u = m?.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return nil }
        return u.absoluteString
    }
}
