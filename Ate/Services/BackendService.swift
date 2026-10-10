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
    static var shareHost: String { string("AteShareHost").isEmpty ? "https://recipe-transform-ai.lovable.app" : string("AteShareHost") }

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
        let server: BackendService = {
            if let url = supabaseURL { return SupabaseBackend(baseURL: url, publishableKey: supabasePublishableKey) }
            return MockBackend()
        }()
        switch backendMode {
        case "mock": return MockBackend()
        case "supabase": return server
        default: return OnDeviceBackend(fallback: server)
        }
    }
}

// MARK: - Mock (default)

final class MockBackend: BackendService {
    private static var published: [String: RecipeCard] = [:]

    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
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
            return card
        }
        let seed = (request.text ?? "").trimmingCharacters(in: .whitespaces)
        let title: String
        switch request.mode {
        case .prompt: title = seed.isEmpty ? "Weeknight miso salmon" : seed.prefix(1).uppercased() + seed.dropFirst()
        case .url: title = "Recipe from \(URL(string: seed)?.host ?? "the web")"
        case .image: title = "Screenshot recipe"
        case .rewrite: title = "Recipe"
        }
        return RecipeCard(
            title: String(title.prefix(80)),
            description: "A demo card from the mock backend — connect Supabase for real AI.",
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
            sourceURL: request.mode == .url ? seed : nil)
    }

    func publish(_ card: RecipeCard) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let slug = String((0..<8).map { _ in chars.randomElement()! })
        Self.published[slug] = card
        return slug
    }

    func fetchShared(slug: String) async throws -> RecipeCard? {
        try await Task.sleep(nanoseconds: 300_000_000)
        if let c = Self.published[slug] { return c }
        if slug == "demo" { return try await parseRecipe(ParseRequest(mode: .prompt, text: "Shared miso salmon")) }
        return nil
    }
}

// MARK: - Supabase / Edge Functions (stub — wire up functions `parse-recipe` and `publish-recipe`)

final class SupabaseBackend: BackendService {
    let baseURL: URL
    let publishableKey: String
    init(baseURL: URL, publishableKey: String) { self.baseURL = baseURL; self.publishableKey = publishableKey }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !publishableKey.isEmpty {
            r.setValue(publishableKey, forHTTPHeaderField: "apikey")
            r.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        }
        r.httpBody = body
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: r)
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
        let data = try await send(request("functions/v1/publish-recipe", method: "POST", body: try JSONEncoder().encode(["card": card])))
        return try JSONDecoder().decode(SlugEnvelope.self, from: data).slug
    }

    func fetchShared(slug: String) async throws -> RecipeCard? {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent("rest/v1/shared_recipes"), resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [URLQueryItem(name: "slug", value: "eq.\(slug)"), URLQueryItem(name: "select", value: "card")]
        guard let url = comps.url else { return nil }
        var r = request("")
        r.url = url
        let data = try await send(r)
        return try JSONDecoder().decode([CardEnvelope].self, from: data).first?.card
    }
}
