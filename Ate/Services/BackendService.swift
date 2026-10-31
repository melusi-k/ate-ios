import Foundation

enum ParseMode: String, Codable { case url, image, prompt, rewrite }

struct ParseRequest: Codable {
    var mode: ParseMode
    var text: String?
    var imageDataUrl: String?
    var currentRecipe: RecipeCard?
}

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func http(_ code: Int) -> BackendError {
        switch code {
        case 429: return BackendError(message: "Rate limit reached — try again in a moment.")
        case 402: return BackendError(message: "AI credits exhausted. Add credits to keep cooking.")
        default: return BackendError(message: "AI returned an unreadable recipe. Try again.")
        }
    }
}

/// All AI + sharing calls go through this protocol. No secret keys ever live in the app.
protocol BackendService {
    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard
    func publish(_ card: RecipeCard) async throws -> String   // returns slug
    func fetchShared(slug: String) async throws -> RecipeCard?
}

enum AppConfig {
    static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    static var backendMode: String { string("AteBackendMode").isEmpty ? "ondevice" : string("AteBackendMode") }
    static var supabaseURL: URL? { URL(string: string("AteSupabaseURL")).flatMap { $0.host == nil ? nil : $0 } }
    /// Publishable (anon) key only — safe to ship; RLS restricts it to SELECT.
    static var supabasePublishableKey: String { string("AteSupabasePublishableKey") }
    static var privacyURL: URL? { URL(string: string("AtePrivacyURL")).flatMap { $0.host == nil ? nil : $0 } }
    static var termsURL: URL? { URL(string: string("AteTermsURL")).flatMap { $0.host == nil ? nil : $0 } }
    static var appVersion: String { string("CFBundleShortVersionString") }
    static var buildNumber: String { string("CFBundleVersion") }
    static var gitSHA: String { string("AteGitSHA").isEmpty ? "dev" : string("AteGitSHA") }
    static var gitSHAFull: String { string("AteGitSHAFull").isEmpty ? gitSHA : string("AteGitSHAFull") }
    static var gitRunID: String { string("AteGitRunID") }
    static var backendRef: String { supabaseURL?.host?.components(separatedBy: ".").first ?? "none" }
    /// e.g. "ate 0.1.12 (build 12) · 306e343 · backend ploncuhexmwydjxljuhe"
    /// Release channel (build setting ATE_CHANNEL, e.g. "TierA"); empty/unknown channels are treated as production.
    static var channel: String { string("AteChannel") }
    /// Fail closed: internal diagnostics are visible only in explicitly named non-production channels.
    /// Empty, unknown, and Production channels must never expose beta UI.
    static let betaChannels: Set<String> = ["TierA", "TierB", "TierC", "Beta", "QA", "Internal", "Development"]
    static func isBetaChannel(_ value: String) -> Bool {
        betaChannels.contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    static var isBetaBuild: Bool {
        let args = ProcessInfo.processInfo.arguments
        // QA overrides are honored only by UI-test launches. An installed production
        // archive can never expose internal diagnostics through a launch argument.
        if isUITesting {
            if args.contains("-qaProductionChannel") { return false }
            if args.contains("-qaBetaChannel") { return true }
            return true
        }
        return isBetaChannel(channel)
    }
    /// "0.1.40 (40) TierA" — CFBundleShortVersionString stays numeric; the channel is display-only.
    static var buildLabel: String { "\(appVersion) (\(buildNumber))" + (channel.isEmpty ? "" : " \(channel)") }
    static var versionLine: String { "ate \(appVersion) (build \(buildNumber))\(channel.isEmpty ? "" : " · " + channel) · \(gitSHA) · backend \(backendRef)" }
    static var shareHost: String { string("AteShareHost").isEmpty ? "https://melusi-k.github.io/ate-legal" : string("AteShareHost") }
    /// Full share-link template with `{slug}`; see ShareLinks.
    static var shareURLTemplate: String { string("AteShareURLTemplate").contains("{slug}") ? string("AteShareURLTemplate") : ShareLinks.defaultTemplate }
    static func shareURL(slug: String) -> String { ShareLinks.url(slug: slug, template: shareURLTemplate) }

    /// Modes: "ondevice" (default: Foundation Models + Vision, mock fallback), "mock", "supabase".
    /// Launched by XCUITest: mock AI, in-memory store, no permission prompts.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-UITesting") }

    /// Optional deep link passed as `-ateOpenURL <url>` (used by UI tests).
    static var launchURL: URL? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-ateOpenURL"), i + 1 < a.count else { return nil }
        return URL(string: a[i + 1])
    }

    static func makeBackend() -> BackendService {
        if isUITesting { return MockBackend() }
        switch backendMode {
        case "mock": return MockBackend()
        case "supabase":
            if let url = supabaseURL { return SupabaseBackend(baseURL: url, publishableKey: supabasePublishableKey) }
            return MockBackend()
        // AI runs on-device (mock fallback); sharing goes to the Supabase edge function `publish-recipe`
        // and reads `shared_recipes` (public RLS). There is no server `parse-recipe`, so AI never hits the server.
        default:
            if let url = supabaseURL {
                return OnDeviceBackend(fallback: MockBackend(), sharing: SupabaseBackend(baseURL: url, publishableKey: supabasePublishableKey))
            }
            return OnDeviceBackend(fallback: MockBackend())
        }
    }
}

// MARK: - Mock (default)

final class MockBackend: BackendService {
    static let downMessage = "ate's server isn't responding right now (HTTP 503). Your recipes are safe on this iPhone. Try again in a moment."
    private static var published: [String: RecipeCard] = [:]
    private static var offlineOnce = true

    private static var parses = 0
    private static var imageParses = 0
    private static var didFailOnceForRetryQA = false
    static let args = ProcessInfo.processInfo.arguments
    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
        // QA hooks: -qaSlowGenerate keeps a generation running (kill mid-generation, A-CREATE-05);
        // -qaBackendDown fails every generation after the first (A-SHARE-05 / backend outage);
        // -qaBackendFailOnce proves Retry starts a fresh request and can recover.
        if Self.args.contains("-qaSlowGenerate") { try await Task.sleep(nanoseconds: 90_000_000_000) }
        if Self.args.contains("-qaBackendDown"), Self.parses >= 1 {
            try await Task.sleep(nanoseconds: 300_000_000)
            throw BackendError(message: MockBackend.downMessage)
        }
        if Self.args.contains("-qaBackendFailOnce"), !Self.didFailOnceForRetryQA {
            Self.didFailOnceForRetryQA = true
            try await Task.sleep(nanoseconds: 300_000_000)
            throw BackendError(message: MockBackend.downMessage)
        }
        Self.parses += 1
        try await Task.sleep(nanoseconds: 900_000_000)
        if request.mode == .rewrite, var card = request.currentRecipe {
            let ask = request.text ?? ""
            card.title = card.title + (ask.isEmpty ? "" : " (\(ask.lowercased()))")
            if ask.lowercased().contains("vegan") {
                card.ingredients = card.ingredients.map { i in
                    var i = i
                    let n = i.name.lowercased()
                    if n.contains("butter") { i.name = "vegan butter" }
                    else if n.contains("milk") { i.name = "oat milk" }
                    else if n.contains("chicken") || n.contains("beef") { i.name = "firm tofu" }
                    else if n.contains("egg") { i.name = "flax egg" }
                    return i
                }
                if !card.tags.contains("vegan") { card.tags.append("vegan") }
            }
            card.source = .mock; card.generatedAt = Date().timeIntervalSince1970 * 1000
            return card
        }
        let seed = (request.text ?? "").trimmingCharacters(in: .whitespaces)
        // QA fixtures: real JSON-LD + social-caption parsers on bundled pages.
        if request.mode == .url, seed.hasPrefix(QAFixtures.jsonLDURL), var c = JSONLD.recipe(fromHTML: QAFixtures.jsonLDHTML, sourceURL: seed) {
            c.source = .jsonLD; c.generatedAt = Date().timeIntervalSince1970 * 1000; return c
        }
        if request.mode == .url, let u = URL(string: seed), let p = SocialLinks.platform(of: u), seed.contains("qafixture") {
            let caption = SocialLinks.caption(platform: p, oEmbed: nil, meta: SocialLinks.meta(QAFixtures.instagramHTML))
            guard SocialLinks.isUseful(caption) else { throw SocialCaptionError(platform: p) }
            var c = QAFixtures.cardFromCaption(caption, sourceURL: SocialLinks.clean(u).absoluteString)
            c.source = .mock; c.generatedAt = Date().timeIntervalSince1970 * 1000; return c
        }
        // QA fixture: a food spread that needs "What dish is this?" (A-CREATE-03 photo step).
        if request.mode == .image, Self.args.contains("-qaSpreadPhoto") {
            guard let dish = request.text, !dish.isEmpty else {
                throw PhotoNeedsDishError(suggestions: ["mogodu", "ujeqe", "morogo", "chakalaka"], spread: true)
            }
            var c = RecipeCard(title: dish.capitalized, description: "From your spread photo.", servings: 4, timeMinutes: 60,
                               ingredients: [Ingredient(name: dish, quantity: 1, unit: "kg", notes: nil)],
                               steps: [Step(order: 1, instruction: "Cook the \(dish).", timeSeconds: nil)])
            c.source = .photoGuess; c.generatedAt = Date().timeIntervalSince1970 * 1000; return c
        }
        // Photos: real Vision OCR decides screenshot vs food photo, even in the mock.
        if request.mode == .image {
            Self.imageParses += 1
            // Keep the photo-fallback UI test deterministic: its first image is a text
            // screenshot (OCR path), and its second is a text-free food photo with no
            // usable Vision labels. Vision label interpretation is covered separately
            // by PhotoGuess unit tests; simulator taxonomy output must not gate this UI test.
            if Self.args.contains("-qaFoodPhotoAfterFirstImage"), Self.imageParses > 1 {
                throw BackendError(message: "Couldn't recognise a dish in that photo. Try a closer shot, a screenshot of the recipe, or describe it in Prompt.")
            }
            let text = (try? await OnDeviceBackend.ocr(dataURL: request.imageDataUrl ?? "")) ?? ""
            if !PhotoGuess.isScreenshotText(text) {
                let labels = (try? await OnDeviceBackend.classify(dataURL: request.imageDataUrl ?? "")) ?? []
                guard let dish = PhotoGuess.dishes(from: labels).first, PhotoGuess.prompt(labels: labels, ocrText: text) != nil else {
                    throw BackendError(message: "Couldn't recognise a dish in that photo. Try a closer shot, a screenshot of the recipe, or describe it in Prompt.")
                }
                var c = RecipeCard(title: "Guessed: " + dish.capitalized, description: "Drafted from a photo — check quantities.",
                                   servings: 2, timeMinutes: 30, ingredients: [Ingredient(name: dish, quantity: 1, unit: "pcs", notes: nil)],
                                   steps: [Step(order: 1, instruction: "Prepare the \(dish).", timeSeconds: nil)])
                c.source = .photoGuess; c.generatedAt = Date().timeIntervalSince1970 * 1000; return c
            }
        }
        // UI-test hook: a social link with no caption.
        if request.mode == .url, let u = URL(string: seed), let p = SocialLinks.platform(of: u), seed.contains("nocaption") {
            throw SocialCaptionError(platform: p)
        }
        let title: String
        switch request.mode {
        case .prompt: title = seed.isEmpty ? "Weeknight miso salmon" : seed.prefix(1).uppercased() + seed.dropFirst()
        case .url: title = "Recipe from \(URL(string: seed)?.host ?? "the web")"
        case .image: title = "Screenshot recipe"
        case .rewrite: title = "Recipe"
        }
        return RecipeCard(
            title: String(title.prefix(80)),
            description: "Demo card — on-device AI isn't available on this device.",
            servings: 2, timeMinutes: 25, tags: ["quick", "demo"],
            ingredients: [
                Ingredient(name: "salmon fillets", quantity: 2, unit: "pcs", notes: nil),
                Ingredient(name: "white miso", quantity: 2, unit: "tbsp", notes: nil),
                Ingredient(name: "honey", quantity: 1, unit: "tbsp", notes: nil),
                Ingredient(name: "garlic", quantity: 2, unit: "cloves", notes: "finely chopped"),
                Ingredient(name: "rice", quantity: 150, unit: "g", notes: nil),
            ],
            steps: [
                Step(order: 1, instruction: "Heat the oven to 200°C and line a tray.", timeSeconds: nil),
                Step(order: 2, instruction: "Mix miso, honey and garlic; brush over the salmon.", timeSeconds: nil),
                Step(order: 3, instruction: "Roast the salmon until just flaky.", timeSeconds: 600),
                Step(order: 4, instruction: "Rest for a minute, then serve over rice.", timeSeconds: 60),
            ],
            sourceURL: request.mode == .url ? seed : nil,
            source: .mock, generatedAt: Date().timeIntervalSince1970 * 1000)
    }

    func publish(_ card: RecipeCard) async throws -> String {
        if Self.args.contains("-qaSharePublishDown") {
            throw BackendError(message: MockBackend.downMessage)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let slug = String((0..<8).map { _ in chars.randomElement()! })
        Self.published[slug] = card
        return slug
    }

    func fetchShared(slug: String) async throws -> RecipeCard? {
        try await Task.sleep(nanoseconds: 300_000_000)
        if let c = Self.published[slug] { return c }
        if slug == "offline" {
            if Self.offlineOnce { Self.offlineOnce = false; throw URLError(.notConnectedToInternet) }
            return try await parseRecipe(ParseRequest(mode: .prompt, text: "Back online soup"))
        }
        if slug == "demo" { return try await parseRecipe(ParseRequest(mode: .prompt, text: "Shared miso salmon")) }
        return nil
    }
}

// MARK: - Supabase / Edge Functions (`publish-recipe` deployed; `parse-recipe` not deployed: no server AI key)

final class SupabaseBackend: BackendService {
    let baseURL: URL
    let publishableKey: String
    init(baseURL: URL, publishableKey: String) { self.baseURL = baseURL; self.publishableKey = publishableKey }
    /// Signed-in user's access token. Production publishing requires this token.
    static var userAccessToken: (() -> String?)?

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !publishableKey.isEmpty { Net.authorize(&r, key: publishableKey) }
        r.httpBody = body
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, resp) = try await Net.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw BackendError.http(code) }
        return data
    }

    struct CardEnvelope: Decodable { let card: RecipeCard }
    struct SlugEnvelope: Decodable { let slug: String }

    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
        let data = try await send(self.request("functions/v1/parse-recipe", method: "POST", body: try JSONEncoder().encode(request)))
        if let env = try? JSONDecoder().decode(CardEnvelope.self, from: data) { return env.card }
        if let card = try? JSONDecoder().decode(RecipeCard.self, from: data) { return card }
        throw BackendError.http(0)
    }

    func publish(_ card: RecipeCard) async throws -> String {
        // Only an https cover URL travels with the share (stored inside the `card` jsonb); local cover files never leave the phone.
        var card = card
        card.imageURL = CoverLogic.httpsURL(card.imageURL)?.absoluteString
        card.coverImage = nil
        var r = request("functions/v1/publish-recipe", method: "POST", body: try JSONEncoder().encode(["card": card]))
        if let token = Self.userAccessToken?() { Net.authorize(&r, key: publishableKey, bearer: token) }
        do {
            let data = try await send(r)
            return try JSONDecoder().decode(SlugEnvelope.self, from: data).slug
        } catch let e as BackendError {
            throw BackendError(message: e.message.hasPrefix("Rate") ? e.message : "Couldn't create a share link. Check your connection and try again.")
        }
    }

    func fetchShared(slug: String) async throws -> RecipeCard? {
        // Read by opaque slug through the edge function, not PostgREST table SELECT.
        // This lets the database revoke public table listing without breaking this client.
        guard var comps = URLComponents(url: baseURL.appendingPathComponent("functions/v1/get-shared-recipe"), resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "slug", value: slug)]
        guard let url = comps.url else { return nil }
        var r = request("")
        r.url = url
        let (data, response) = try await Net.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard (200..<300).contains(code) else { throw BackendError.http(code) }
        return try JSONDecoder().decode(CardEnvelope.self, from: data).card
    }
}
