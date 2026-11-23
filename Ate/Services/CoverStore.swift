import SwiftUI
import UIKit
#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Single-resume race box for `CoverStore.withTerminalDeadline`: first `resume` wins.
/// File scope on purpose - a local type inside a generic function cannot capture the
/// function's generic parameter, so this must live outside it to compile.
final class ResumeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var resolved: T??
    func resume(with value: T?) {
        lock.lock()
        if let stored = resolved {
            lock.unlock(); _ = stored; return
        }
        resolved = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
    func wait() async -> T? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let value = resolved {
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

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
    /// Shimmer ownership: each in-flight cover operation (a resolve, a generation attempt)
    /// holds one count for the recipe; the `loading` marker clears only when the last
    /// holder releases. No operation - including an older resolve or a superseded
    /// generation attempt - can clear another operation's shimmer.
    @ObservationIgnored private var loadingHolders: [String: Int] = [:]

    /// Takes one shimmer hold for the recipe. Callers: resolve and runCoverAttempt.
    func beginCoverLoading(_ id: String) {
        loadingHolders[id, default: 0] += 1
        loading.insert(id)
    }

    /// Releases one shimmer hold; the marker clears when the last holder releases.
    func endCoverLoading(_ id: String) {
        let n = (loadingHolders[id] ?? 1) - 1
        if n <= 0 { loadingHolders[id] = nil; loading.remove(id) } else { loadingHolders[id] = n }
    }
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
        beginCoverLoading(r.id); defer { endCoverLoading(r.id) }
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
            // The availability init can hang on the same uncooperative system path as the
            // generation stream, so it runs under the same terminal deadline: a hung check
            // resolves to "unavailable" (tile fallback) instead of an unbounded await.
            let outcome: (Bool, String)? = await withTerminalDeadline(seconds: generationDeadlineSeconds) { () async -> (Bool, String)? in
                do {
                    let c = try await ImageCreator()
                    let ok = !c.availableStyles.isEmpty
                    return (ok, ok ? "ImageCreator ready (\(c.availableStyles.count) styles)" : "ImageCreator: no styles")
                } catch { return (false, "ImageCreator unavailable: \(error.localizedDescription)") }
            }
            playgroundAvailable = outcome?.0 ?? false
            playgroundStatus = outcome?.1 ?? "ImageCreator availability check timed out"
            return
        }
        playgroundStatus = "needs iOS 18.4"
        #else
        playgroundStatus = "ImagePlayground not in SDK"
        #endif
    }

    /// One generation attempt must reach a terminal state even when the system stream
    /// never settles: after this bound the attempt reports failure, `loading` clears and
    /// the Shimmer stops, so the app can idle again. The branded tile is the designed
    /// fallback; a result produced after the deadline is ineligible at the effect boundary.
    nonisolated static let generationDeadlineSeconds: UInt64 = 45

    /// First completion wins: the operation's value, or nil once the deadline passes.
    /// Unstructured on purpose: a structured task group would still wait for a hung,
    /// cancellation-uncooperative system stream at scope exit. After the winner is known
    /// both loser tasks are cancelled (the timer so a fast success does not keep a 45s
    /// sleep alive, the operation as a cooperative-cleanup best effort); a stream that
    /// ignores cancellation ends unread - this function retains nothing after return,
    /// and late-write safety comes from the caller's effect boundary, not cancellation.
    nonisolated static func withTerminalDeadline<T>(seconds: UInt64, _ operation: @escaping () async -> T?) async -> T? {
        let box = ResumeBox<T>()
        let work = Task { box.resume(with: await operation()) }
        let timer = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            box.resume(with: nil)
        }
        let result = await box.wait()
        work.cancel()
        timer.cancel()
        return result
    }

    /// Monotonic per-recipe attempt identity. Only the latest attempt may commit a cover
    /// at the effect boundary; a superseded or deadline-losing attempt's product is dropped.
    @ObservationIgnored private var coverGenerationAttempts: [String: UInt64] = [:]

    /// Attempt seam, token half: begins a generation attempt, superseding any earlier one.
    func beginCoverAttempt(for r: RecipeCard) -> UInt64 {
        let next = (coverGenerationAttempts[r.id] ?? 0) + 1
        coverGenerationAttempts[r.id] = next
        return next
    }

    /// Attempt seam, commit half - the effect boundary generate() commits through and tests
    /// drive directly: only a winning product from the still-current attempt, re-proven
    /// against the writer epoch, may write a cover. Cancellation of a loser task is cleanup
    /// only; this guard is what makes a late or stale write impossible.
    @discardableResult
    func commitGeneratedCover(_ produced: CGImage?, attempt: UInt64, for r: RecipeCard) -> String? {
        guard let produced,
              coverGenerationAttempts[r.id] == attempt,
              (try? validateWriter()) != nil else { return nil }
        return save(UIImage(cgImage: produced), recipeID: r.id, source: .generated)
    }

    /// Attempt seam, runner: token, shimmer state, deadline race over the producer, then
    /// commit at the effect boundary. Production calls it with the Image Playground
    /// producer; tests drive it with synthetic producers (hung, late, failing) so the
    /// behavior under test is the production path itself, not a copy of it.
    func runCoverAttempt(for r: RecipeCard, seconds: UInt64 = CoverStore.generationDeadlineSeconds, produce: @escaping () async -> CGImage?) async -> String? {
        let attempt = beginCoverAttempt(for: r)
        beginCoverLoading(r.id)
        defer { endCoverLoading(r.id) }
        // Production only: the stream result leaves the race as a value. Nothing here
        // writes state, so a product that arrives after the deadline has no effect.
        let produced = await Self.withTerminalDeadline(seconds: seconds, produce)
        return commitGeneratedCover(produced, attempt: attempt, for: r)
    }

    /// Generates an illustration from the title + main ingredients. Returns nil on any error.
    func generate(for r: RecipeCard) async -> String? {
        // The attempted marker is a mutation and goes through the writer boundary.
        try? writerBoundary.withEffect {
            UserDefaults.standard.set(true, forKey: "ate.cover.gen.\(r.id)")
        }
        #if canImport(ImagePlayground)
        if #available(iOS 18.4, *) {
            return await runCoverAttempt(for: r) {
                do {
                    let creator = try await ImageCreator()
                    let styles = creator.availableStyles
                    guard let style = styles.contains(.illustration) ? ImagePlaygroundStyle.illustration : styles.first else { return nil }
                    let text = CoverLogic.concept(title: r.title, ingredients: r.ingredients.map(\.name))
                    for try await img in creator.images(for: [.text(text)], style: style, limit: 1) {
                        return img.cgImage
                    }
                } catch { return nil }
                return nil
            }
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
