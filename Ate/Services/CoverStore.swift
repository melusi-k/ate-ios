import SwiftUI
import UIKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Recipe cover images: local JPEG files (App Group or app container), an in-memory cache,
/// lazy backfill (og:image / oEmbed thumbnail) and optional on-device Image Playground generation.
/// Everything here is async and best-effort; it never blocks saving a recipe.
@Observable
@MainActor
final class CoverStore {
    static let shared = CoverStore()

    private var cache: [String: UIImage] = [:]
    /// Recipe ids with a cover being fetched/generated (drives the shimmer).
    private(set) var loading: Set<String> = []
    @ObservationIgnored private var attempted: Set<String> = []
    /// Writer seam (#245, lane 3): production composition injects the shared boundary
    /// and a post-await validator; the defaults preserve today's behavior exactly.
    @ObservationIgnored var writerBoundary: FoodJournalWriterBoundary = .legacy
    @ObservationIgnored var validateWriter: () throws -> Void = {}

    // MARK: files

    /// Where covers live. The App Group container is shared with the widgets; a sideload
    /// without the group runs in a declared `.appOnly` mode rather than silently
    /// pretending the widgets can see the files.
    nonisolated enum ContainerMode: String { case shared, appOnly }
    nonisolated static var containerMode: ContainerMode {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedContainer.groupID) != nil ? .shared : .appOnly
    }

    nonisolated static var folder: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedContainer.groupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    nonisolated static func url(_ file: String) -> URL { folder.appendingPathComponent(file) }

    func image(for r: RecipeCard) -> UIImage? {
        guard let f = r.coverImage, f != Self.removed else { return nil }
        if let i = cache[f] { return i }
        guard let i = UIImage(contentsOfFile: Self.url(f).path) else { return nil }
        cache[f] = i
        return i
    }
    func isLoading(_ id: String) -> Bool { loading.contains(id) }

    /// Crop to 4:3, downscale to ≤1200 px wide, JPEG 0.8.
    nonisolated static func process(_ image: UIImage) -> Data? {
        guard let cg = image.normalizedCG() else { return nil }
        let c = CoverLogic.crop43(width: Double(cg.width), height: Double(cg.height))
        guard let cropped = cg.cropping(to: CGRect(x: c.x, y: c.y, width: c.w, height: c.h)) else { return nil }
        let w = min(1200, CGFloat(cropped.width)), h = (w * 3 / 4).rounded()
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out.jpegData(compressionQuality: 0.8)
    }

    /// Writes a cover and returns its file name (old covers for the recipe are removed).
    @discardableResult
    func save(_ image: UIImage, recipeID: String, source: CoverLogic.Source) -> String? {
        // One gated effect covers the whole mutation: process, remove old covers, write
        // the file and publish the cache entry.
        try? writerBoundary.withEffect {
            guard let data = Self.process(image) else { return nil }
            let name = CoverLogic.fileName(for: recipeID, source: source)
            removeFiles(recipeID: recipeID, except: name)
            do { try data.write(to: Self.url(name), options: .atomic) } catch { return nil }
            cache[name] = UIImage(data: data)
            return name
        }
    }

    func removeFiles(recipeID: String, except keep: String? = nil) {
        try? writerBoundary.withEffect {
            for s in CoverLogic.Source.allCases {
                let n = CoverLogic.fileName(for: recipeID, source: s)
                if n == keep { continue }
                cache[n] = nil
                try? FileManager.default.removeItem(at: Self.url(n))
            }
        }
    }

    // MARK: lazy backfill

    /// Sentinel `coverImage` value: the user removed the cover; show the tile and don't backfill.
    nonisolated static let removed = "none"

    /// Called when a cover appears: downloads a remote image or finds the page image once per launch.
    func ensure(_ r: RecipeCard, store: AppStore) {
        if r.coverImage == Self.removed || image(for: r) != nil || attempted.contains(r.id) { return }
        if CoverLogic.source(ofFile: r.coverImage) == .userPhoto { return } // the photo lives on another device
        attempted.insert(r.id)
        Task {
            // The launch-time Playground check may not have finished yet; never decide "tile" before it has.
            if Self.playgroundStatus == "not checked" { await Self.checkPlayground() }
            guard CoverLogic.httpsURL(r.imageURL) != nil || CoverLogic.httpsURL(r.sourceURL) != nil || shouldAutoGenerate(r) else {
                attempted.remove(r.id); return
            }
            if let res = await resolve(r) {
                // Late async completion: re-prove the writer boundary after the awaits
                // before publishing into the store; a reset in between drops the result.
                guard (try? validateWriter()) != nil else { return }
                store.setCover(r.id, file: res.file, imageURL: res.imageURL)
            }
        }
    }

    /// Finds a cover for a recipe without a user photo: remote image → page image → Image Playground.
    func resolve(_ r: RecipeCard, allowGenerate: Bool = true) async -> (file: String, imageURL: String?)? {
        loading.insert(r.id); defer { loading.remove(r.id) }
        var imageURL = CoverLogic.httpsURL(r.imageURL)
        if imageURL == nil, let page = CoverLogic.httpsURL(r.sourceURL) { imageURL = await Self.findPageImage(page) }
        if let u = imageURL, let img = await Self.download(u) {
            // Epoch re-check after the network await: never write a cover fetched for a
            // store state that a reset or account change has since replaced.
            guard (try? validateWriter()) != nil else { return nil }
            if let name = save(img, recipeID: r.id, source: .pageImage) { return (name, u.absoluteString) }
        }
        if allowGenerate, shouldAutoGenerate(r), let name = await generate(for: r) { return (name, nil) }
        return nil
    }

    /// Image Playground is tried for every recipe whose web image path came up empty (Instagram/TikTok pages often
    /// expose no og:image), not only prompt recipes, so the branded tile is truly the last resort.
    private func shouldAutoGenerate(_ r: RecipeCard) -> Bool {
        Self.playgroundAvailable
            && !UserDefaults.standard.bool(forKey: "ate.cover.gen.\(r.id)")
    }

    nonisolated static func download(_ url: URL) async -> UIImage? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (d, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400, d.count < 15_000_000 else { return nil }
        return UIImage(data: d)
    }

    /// og:image / JSON-LD image for web pages; oEmbed thumbnail (YouTube/TikTok) or og:image for social posts.
    nonisolated static func findPageImage(_ page: URL) async -> URL? {
        if let o = SocialLinks.oEmbedURL(for: page),
           let (d, _) = try? await URLSession.shared.data(from: o),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let t = CoverLogic.oEmbedThumbnail(j) { return t }
        var req = URLRequest(url: page, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return CoverLogic.pageImage(fromHTML: String(decoding: d.prefix(1_500_000), as: UTF8.self), baseURL: page)
    }

    // MARK: Image Playground (ImageCreator, iOS 18.4+)

    /// Set at launch from `ImageCreator()`; false when the API, device or region doesn't support it.
    private(set) static var playgroundAvailable = false
    static var playgroundStatus = "not checked"

    static func checkPlayground() async {
        #if canImport(ImagePlayground)
        if #available(iOS 18.4, *) {
            do {
                let c = try await ImageCreator()
                playgroundAvailable = !c.availableStyles.isEmpty
                playgroundStatus = playgroundAvailable ? "ImageCreator ready (\(c.availableStyles.count) styles)" : "ImageCreator: no styles"
            } catch { playgroundAvailable = false; playgroundStatus = "ImageCreator unavailable: \(error.localizedDescription)" }
            return
        }
        playgroundStatus = "needs iOS 18.4"
        #else
        playgroundStatus = "ImagePlayground not in SDK"
        #endif
    }

    /// Generates an illustration from the title + main ingredients. Returns nil on any error.
    func generate(for r: RecipeCard) async -> String? {
        // The attempted marker is a mutation and goes through the writer boundary.
        try? writerBoundary.withEffect {
            UserDefaults.standard.set(true, forKey: "ate.cover.gen.\(r.id)")
        }
        #if canImport(ImagePlayground)
        if #available(iOS 18.4, *) {
            let wasLoading = loading.contains(r.id)
            loading.insert(r.id); defer { if !wasLoading { loading.remove(r.id) } }
            do {
                let creator = try await ImageCreator()
                let styles = creator.availableStyles
                guard let style = styles.contains(.illustration) ? ImagePlaygroundStyle.illustration : styles.first else { return nil }
                let text = CoverLogic.concept(title: r.title, ingredients: r.ingredients.map(\.name))
                for try await img in creator.images(for: [.text(text)], style: style, limit: 1) {
                    // Epoch re-check after the generator await: a cover produced for a
                    // pre-reset state is dropped, never written.
                    guard (try? validateWriter()) != nil else { return nil }
                    return save(UIImage(cgImage: img.cgImage), recipeID: r.id, source: .generated)
                }
            } catch { return nil }
        }
        #endif
        return nil
    }
}

private extension UIImage {
    /// CGImage with orientation applied.
    func normalizedCG() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}
