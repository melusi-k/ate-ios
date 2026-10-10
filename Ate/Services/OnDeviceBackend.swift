import Foundation
import Vision
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI: Apple Foundation Models (iOS 26+) for structuring, Vision OCR for screenshots.
/// Falls back to `fallback` (mock by default) when the system model is unavailable.
/// Sharing (publish/fetch) goes to `sharing` (Supabase) when configured, otherwise to `fallback`.
final class OnDeviceBackend: BackendService {
    let fallback: BackendService
    let sharing: BackendService
    init(fallback: BackendService, sharing: BackendService? = nil) { self.fallback = fallback; self.sharing = sharing ?? fallback }

    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var availabilityDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "On-device Apple Intelligence model"
            case .unavailable(let reason): return "On-device model unavailable (\(String(describing: reason))) — using demo AI"
            @unknown default: return "On-device model unavailable — using demo AI"
            }
        }
        #endif
        return "On-device AI needs iOS 26 + Apple Intelligence — using demo AI"
    }

    func parseRecipe(_ request: ParseRequest) async throws -> RecipeCard {
        // Links: structured schema.org/Recipe data first (no AI needed), then the model.
        var pageHTML: String?
        var socialCaption: String?
        if request.mode == .url, let u = URL(string: (request.text ?? "").trimmingCharacters(in: .whitespaces)),
           let platform = SocialLinks.platform(of: u) {
            let clean = SocialLinks.clean(u)
            let caption = await Self.fetchSocialCaption(clean, platform: platform)
            guard SocialLinks.isUseful(caption) else { throw SocialCaptionError(platform: platform) }
            if CaptionAnalysis.isUngroundedPromo(caption) {
                throw SocialCaptionError(platform: platform, reason: "This \(platform.rawValue) post is an advert with no recipe or dish name. Tell ate the dish in Prompt (e.g. “mogodu”) instead.")
            }
            socialCaption = caption
        } else if request.mode == .url {
            if let html = try? await Self.fetchHTML(request.text ?? "") {
                pageHTML = html
                if var card = JSONLD.recipe(fromHTML: html, sourceURL: request.text) {
                    card.source = .jsonLD; card.generatedAt = Date().timeIntervalSince1970 * 1000
                    return RecipeLogic.normalize(card)
                }
            }
        }
        guard Self.isModelAvailable else { return try await fallback.parseRecipe(request) }
        var source: RecipeSource = .appleIntelligence
        let prompt: String
        switch request.mode {
        case .prompt:
            prompt = RecipePrompt.prompt(request.text ?? "")
        case .url where socialCaption != nil:
            prompt = RecipePrompt.social(caption: socialCaption!)
        case .url:
            let page: String
            if let html = pageHTML { page = String(Self.htmlToText(html).prefix(3500)) }
            else { page = try await Self.fetchPageText(request.text ?? "") }
            prompt = RecipePrompt.page(page)
        case .image:
            let text = try await Self.ocr(dataURL: request.imageDataUrl ?? "")
            let hint = (request.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if PhotoGuess.isScreenshotText(text) && hint.isEmpty {
                prompt = RecipePrompt.screenshot(text)
            } else {
                // A food photo: OCR + labels; generic labels mean we ask the user before generating.
                let labels = try await Self.classify(dataURL: request.imageDataUrl ?? "")
                let names = PhotoGuess.dishes(from: labels)
                if !hint.isEmpty {
                    prompt = RecipePrompt.photo(dish: hint, labels: names, ocr: text)
                } else {
                    switch PhotoGuess.assess(labels: labels, ocrText: text) {
                    case .confident(let dish): prompt = RecipePrompt.photo(dish: dish, labels: names, ocr: text)
                    case .uncertain(let s): throw PhotoNeedsDishError(suggestions: s, spread: false)
                    case .spread(let s): throw PhotoNeedsDishError(suggestions: s, spread: true)
                    }
                }
                source = .photoGuess
            }
        case .rewrite:
            var c = request.currentRecipe ?? RecipeCard()
            c.imageURL = nil; c.sourceURL = nil
            let json = (try? String(data: JSONEncoder().encode(c), encoding: .utf8)) ?? ""
            prompt = "Rewrite per \"\(request.text ?? "")\":\n\(json)"
        }
        var card = try await Self.generate(prompt)
        card.source = source; card.generatedAt = Date().timeIntervalSince1970 * 1000
        if request.mode == .url, let u = URL(string: (request.text ?? "").trimmingCharacters(in: .whitespaces)) {
            card.sourceURL = SocialLinks.clean(u).absoluteString
        }
        if request.mode == .rewrite, let cur = request.currentRecipe {
            card.id = cur.id; card.createdAt = cur.createdAt; card.favorite = cur.favorite; card.sortIndex = cur.sortIndex; card.lastCookedAt = cur.lastCookedAt; card.source = .appleIntelligence; card.imageURL = cur.imageURL; card.sourceURL = cur.sourceURL
        }
        return RecipeLogic.normalize(card)
    }

    func publish(_ card: RecipeCard) async throws -> String { try await sharing.publish(card) }
    func fetchShared(slug: String) async throws -> RecipeCard? {
        if slug == "demo" { return try await fallback.fetchShared(slug: slug) }
        return try await sharing.fetchShared(slug: slug)
    }

    static let instructions = RecipePrompt.instructions

    static func generate(_ prompt: String) async throws -> RecipeCard {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            do {
                // Extraction, not creative writing: greedy decoding keeps the card grounded in the text.
                let res = try await session.respond(to: prompt, generating: GenRecipe.self, options: GenerationOptions(sampling: .greedy, temperature: 0.1))
                return res.content.card
            } catch {
                throw BackendError(message: "AI returned an unreadable recipe. Try again.")
            }
        }
        #endif
        throw BackendError(message: "On-device AI isn't available on this device.")
    }

    static func fetchPageText(_ link: String) async throws -> String {
        String(htmlToText(try await fetchHTML(link)).prefix(3500))
    }

    static func fetchHTML(_ link: String) async throws -> String {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else {
            throw BackendError(message: "That doesn't look like a link.")
        }
        var r = URLRequest(url: url)
        r.timeoutInterval = 10
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 ate/1.0", forHTTPHeaderField: "User-Agent")
        r.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await Net.data(for: r) }
        catch let e as URLError where e.code == .timedOut {
            throw BackendError(message: "That page took too long to load (10 s). Check the link, or paste the recipe text into Prompt.")
        }
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw BackendError(message: "That page didn't load (HTTP \(code)). Check the link and try again.")
        }
        return String(decoding: data.prefix(1_500_000), as: UTF8.self)
    }

    /// oEmbed (TikTok/YouTube) + OG tags fetched with a link-preview bot UA, ~8 s budget. Never throws: empty = nothing found.
    static func fetchSocialCaption(_ url: URL, platform: SocialLinks.Platform) async -> String {
        func get(_ u: URL, ua: String) async -> Data? {
            var r = URLRequest(url: u); r.timeoutInterval = 8
            r.setValue(ua, forHTTPHeaderField: "User-Agent")
            r.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            guard let (d, resp) = try? await Net.data(for: r), ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400 else { return nil }
            return d
        }
        let bot = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
        let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        let oURL = SocialLinks.oEmbedURL(for: url)
        async let page: Data? = get(url, ua: bot)
        var oeData: Data?
        if let oURL { oeData = await get(oURL, ua: desktop) }
        let oEmbed = oeData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let html = (await page).map { String(decoding: $0.prefix(1_500_000), as: UTF8.self) } ?? ""
        var caption = SocialLinks.caption(platform: platform, oEmbed: oEmbed, meta: SocialLinks.meta(html))
        if !SocialLinks.isUseful(caption), let card = JSONLD.recipe(fromHTML: html, sourceURL: url.absoluteString) {
            caption = RecipeLogic.text(for: card, units: .metric)
        }
        return caption
    }

    static func classify(dataURL: String) async throws -> [(String, Float)] {
        let b64 = dataURL.components(separatedBy: ",").last ?? ""
        guard let data = Data(base64Encoded: b64), let cg = UIImage(data: data)?.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNClassifyImageRequest()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cg).perform([req])
                    let obs = (req.results ?? []).filter { $0.confidence > 0.05 }.prefix(12).map { ($0.identifier, $0.confidence) }
                    cont.resume(returning: Array(obs))
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    static func htmlToText(_ html: String) -> String {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<[^>]+>"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        for (a, b) in ["&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func ocr(dataURL: String) async throws -> String {
        let b64 = dataURL.components(separatedBy: ",").last ?? ""
        guard let data = Data(base64Encoded: b64), let cg = UIImage(data: data)?.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { cont.resume(throwing: error) }
            }
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GenIngredient {
    @Guide(description: "Ingredient name, e.g. 'garlic'") var name: String
    @Guide(description: "Realistic numeric quantity for the servings, 0 only for 'to taste'") var quantity: Double
    @Guide(description: "Metric or short unit: g, kg, ml, l, tbsp, tsp, cloves, pcs, or empty") var unit: String
    @Guide(description: "Optional prep notes, e.g. 'finely chopped'") var notes: String?
}

@available(iOS 26.0, *)
@Generable
struct GenStep {
    @Guide(description: "Concise instruction") var instruction: String
    @Guide(description: "Seconds to wait/cook for this step, only for timed steps") var timeSeconds: Int?
}

@available(iOS 26.0, *)
@Generable
struct GenRecipe {
    @Guide(description: "The dish name exactly as named in the text; never a place, business, hashtag or handle") var title: String
    @Guide(description: "Under 20 words") var description: String
    @Guide(description: "Servings that suit the dish (stews 4 to 6), at least 1") var servings: Int
    @Guide(description: "Total minutes: prep plus the sum of all step times") var timeMinutes: Int
    @Guide(description: "Up to 5 short lowercase tags") var tags: [String]
    @Guide(description: "Cuisine in one or two words, e.g. Italian, Mexican, South African, Thai") var cuisine: String
    @Guide(description: "Ingredients copied from the text when given; realistic metric quantities") var ingredients: [GenIngredient]
    @Guide(description: "Steps in order; timed steps carry timeSeconds") var steps: [GenStep]
    @Guide(description: "0 to 1: how sure you are this card is the dish in the text") var confidence: Double
    @Guide(description: "Short note when the recipe is best-effort (advert/menu, unknown dish), otherwise empty") var note: String

    var card: RecipeCard {
        var c = baseCard
        c.aiConfidence = max(0, min(1, confidence))
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        c.aiNote = n.isEmpty ? nil : n
        // Total time = sum of timed steps when the model's own total is lower.
        let stepMin = (steps.compactMap(\.timeSeconds).reduce(0, +) + 59) / 60
        if stepMin > (c.timeMinutes ?? 0) { c.timeMinutes = stepMin }
        return c
    }

    var baseCard: RecipeCard {
        RecipeCard(title: title, description: description, servings: max(1, servings),
                   timeMinutes: timeMinutes > 0 ? timeMinutes : nil, tags: tags,
                   ingredients: ingredients.map { Ingredient(name: $0.name, quantity: $0.quantity, unit: $0.unit, notes: $0.notes) },
                   steps: steps.enumerated().map { Step(order: $0.offset + 1, instruction: $0.element.instruction,
                                                        timeSeconds: ($0.element.timeSeconds ?? 0) > 0 ? $0.element.timeSeconds : nil) },
                   cuisine: cuisine.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cuisine.trimmingCharacters(in: .whitespaces))
    }
}
#endif
