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
        var input: RecipePrompt.Input = .prompt
        var photoForTool: String?
        var reviseID: String?
        switch request.mode {
        case .prompt:
            prompt = RecipePrompt.prompt(request.text ?? "")
        case .url where socialCaption != nil:
            prompt = RecipePrompt.social(caption: socialCaption!); input = .social
        case .url:
            let page: String
            if let html = pageHTML { page = String(Self.htmlToText(html).prefix(3500)) }
            else { page = try await Self.fetchPageText(request.text ?? "") }
            prompt = RecipePrompt.page(page); input = .link
        case .image:
            let text = try await Self.ocr(dataURL: request.imageDataUrl ?? "")
            let hint = (request.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if PhotoGuess.isScreenshotText(text) && hint.isEmpty {
                prompt = RecipePrompt.screenshot(text); input = .screenshot
            } else {
                // A food photo: OCR + labels; generic labels mean we ask the user before generating.
                let labels = try await Self.classify(dataURL: request.imageDataUrl ?? "")
                let names = PhotoGuess.dishes(from: labels)
                input = .photo; photoForTool = request.imageDataUrl
                let viaTool = Self.toolsAvailable
                if !hint.isEmpty {
                    prompt = RecipePrompt.photo(dish: hint, labels: names, ocr: text, ocrViaTool: viaTool)
                } else {
                    switch PhotoGuess.assess(labels: labels, ocrText: text) {
                    case .confident(let dish): prompt = RecipePrompt.photo(dish: dish, labels: names, ocr: text, ocrViaTool: viaTool)
                    case .uncertain(let s):
                        // Identify inside the generation pass; the sheet only asks when confidence < 80%.
                        prompt = RecipePrompt.photoUnnamed(labels: names, candidates: s, ocr: text, ocrViaTool: viaTool)
                    case .spread(let s): throw PhotoNeedsDishError(suggestions: s, spread: true)
                    }
                }
                source = .photoGuess
            }
        case .rewrite:
            var c = request.currentRecipe ?? RecipeCard()
            c.imageURL = nil; c.sourceURL = nil
            let json = (try? String(data: JSONEncoder().encode(c), encoding: .utf8)) ?? ""
            prompt = "Rewrite per \"\(request.text ?? "")\":\n\(json)"; input = .rewrite
            reviseID = c.id
        }
        var card = try await Self.generate(prompt, input: input, photoDataURL: photoForTool, reviseID: reviseID,
                                           context: RecipePrompt.context(for: request.text ?? ""))
        if let r = reviseID { await Self.rekeySession(from: card.id, to: r) }
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

    /// Tools are part of FoundationModels on iOS 26 (verified in Xcode 26.6's swiftinterface).
    static var toolsAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Live preview sink for the review sheet (set while the Add sheet / Ask Ate is generating).
    @MainActor static var partialSink: ((RecipeStreamPreview) -> Void)?

    #if canImport(FoundationModels)
    /// Sessions kept per recipe id so Ask Ate ("Make this vegan") revises the card in the SAME conversation.
    @available(iOS 26.0, *) @MainActor private static var sessions: [String: LanguageModelSession] = [:]
    @available(iOS 26.0, *) @MainActor private static var warm: LanguageModelSession?
    #endif

    /// Called when the Add recipe sheet opens: loads the model + prompt-instructions prefix ahead of the tap.
    @MainActor static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isModelAvailable, warm == nil {
            let s = makeSession(tools: [RegionalDishTool()], input: .prompt)
            s.prewarm()
            warm = s
        }
        #endif
    }

    /// Readable reason when the model isn't usable (graceful fallback to the template backend is used instead).
    static var availabilityNote: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Apple Intelligence ready"
            case .unavailable(.deviceNotEligible): return "This iPhone doesn't support Apple Intelligence"
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings"
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading"
            case .unavailable: return "Apple Intelligence unavailable"
            }
        }
        #endif
        return "Needs iOS 26"
    }

    @MainActor
    static func generate(_ prompt: String, input: RecipePrompt.Input = .prompt, photoDataURL: String? = nil,
                         reviseID: String? = nil, context: RecipePrompt.Context = .init()) async throws -> RecipeCard {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            var tools: [any Tool] = [RegionalDishTool()]
            if let photoDataURL { tools.append(PhotoTextTool(dataURL: photoDataURL)) }
            let session: LanguageModelSession
            if let id = reviseID, let s = sessions[id] { session = s }                       // Ask Ate: same session
            else if input == .prompt, photoDataURL == nil, let w = warm { session = w; warm = nil } // prewarmed
            else { session = makeSession(tools: tools, input: input) }
            do {
                // Extraction, not creative writing: greedy decoding keeps the card grounded in the text.
                // Streamed so the review sheet renders the PartiallyGenerated card live.
                // Code-along 205: Prompt { } builder with conditional context lines and a one-shot GenRecipe example;
                // with the example in place the JSON schema is left out of the prompt (A/B: -qaIncludeSchema).
                let lines = RecipePrompt.contextLines(context)
                let isRevision = reviseID != nil && sessions[reviseID!] != nil
                let fullPrompt = Prompt {
                    prompt
                    if !lines.isEmpty { lines.joined(separator: "\n") }
                    if !isRevision {
                        RecipePrompt.exampleLead
                        GenRecipe.exampleMogodu
                    }
                }
                let stream = session.streamResponse(to: fullPrompt, generating: GenRecipe.self,
                                                    includeSchemaInPrompt: RecipePrompt.includeSchemaInPrompt || isRevision,
                                                    options: GenerationOptions(sampling: .greedy))
                for try await snap in stream {
                    partialSink?(RecipeStreamPreview(snap.content))
                }
                let res = try await stream.collect()
                let card = res.content.card
                sessions[card.id] = session
                if sessions.count > 8, let k = sessions.keys.first(where: { $0 != card.id }) { sessions[k] = nil }
                return card
            } catch let e as LanguageModelSession.GenerationError {
                throw BackendError(message: GenerationFailure(e).message)
            } catch {
                throw BackendError(message: GenerationFailure.decoding.message)
            }
        }
        #endif
        throw BackendError(message: "On-device AI isn't available on this device.")
    }

    #if canImport(FoundationModels)
    /// Instructions { } builder: persona, rules and format; the glossary now comes from lookupRegionalDish on demand.
    @available(iOS 26.0, *)
    static func makeSession(tools: [any Tool], input: RecipePrompt.Input) -> LanguageModelSession {
        LanguageModelSession(tools: tools, instructions: Instructions {
            RecipePrompt.instructions(for: input)
            "For any regional or unfamiliar dish name, call lookupRegionalDish before writing ingredients."
        })
    }
    #endif

    /// Move a revised card's session to the recipe's stable id (rewrite keeps the original id).
    @MainActor static func rekeySession(from old: String, to new: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), old != new, let s = sessions[old] { sessions[new] = s; sessions[old] = nil }
        #endif
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
/// Vision OCR exposed to the model as a Tool, so text in a food photo is read only when the model wants it.
@available(iOS 26.0, *)
struct PhotoTextTool: Tool {
    let dataURL: String
    let name = "readPhotoText"
    let description = "Reads any printed text (menu board, label, packaging) in the user's food photo. Returns the text, or 'no text'."
    @Generable
    struct Arguments {
        @Guide(description: "Why the text is needed, e.g. 'menu board names the dish'") var reason: String
    }
    func call(arguments: Arguments) async throws -> String {
        let t = (try? await OnDeviceBackend.ocr(dataURL: dataURL)) ?? ""
        let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "no text" : String(clean.prefix(600))
    }
}

/// Glossary on demand (replaces dumping every matching entry into the prompt).
@available(iOS 26.0, *)
struct RegionalDishTool: Tool {
    let name = "lookupRegionalDish"
    let description = "Looks up traditional ingredients, method and cooking time for Southern African dishes (e.g. mogodu, ujeqe, chakalaka, umngqusho, pap, morogo)."
    @Generable
    struct Arguments {
        @Guide(description: "The dish name to look up, e.g. 'mogodu'") var dishName: String
    }
    func call(arguments: Arguments) async throws -> String { RecipePrompt.lookupRegionalDish(arguments.dishName) }
}

@available(iOS 26.0, *)
@Generable
struct GenIngredient {
    @Guide(description: "Realistic numeric amount for the servings; 0 only for 'to taste'", .range(0...5000)) var quantity: Double
    @Guide(description: "Metric or short unit: g, kg, ml, l, tbsp, tsp, cloves, pcs, or empty") var unit: String
    @Guide(description: "Ingredient name, e.g. 'beef short rib'") var name: String
    @Guide(description: "Optional prep, e.g. 'finely chopped'") var prep: String?
}

@available(iOS 26.0, *)
@Generable
struct GenStep {
    @Guide(description: "One specific action starting with a precise verb (sear, simmer, roast, stir in) plus heat level and a doneness cue; never a vague step like 'cook ribs', never a step the source doesn't support") var instruction: String
    @Guide(description: "Minutes this step takes (20 for 'simmer 20 minutes', 180 for '2 to 3 h'); omit for untimed steps, 1 to 720") var minutes: Int?
    @Guide(description: "Oven or oil temperature in °C when the step uses one (oven, deep-fry); otherwise omit; 50 to 300") var temperatureC: Int?
}

/// Step 1 of the single guided pass: who is this dish? Generated BEFORE the recipe, so the recipe is conditioned on it.
@available(iOS 26.0, *)
@Generable
struct DishIdentification {
    @Guide(description: "Most likely dish name from the caption/OCR/image labels and glossary; never a place, business, hashtag or handle") var name: String
    @Guide(description: "Cuisine in one or two words, e.g. South African, Italian") var cuisine: String
    @Guide(description: "How sure you are the dish is `name`; below 0.8 when the input doesn't clearly name or show it", .range(0.0...1.0)) var confidence: Double
    @Guide(description: "Other plausible dish names, most likely first; empty when sure", .maximumCount(4)) var alternatives: [String]
}

/// Nested structured output (Foundation Models code-along pattern): identification first, then the recipe.
@available(iOS 26.0, *)
@Generable
struct GenRecipe {
    @Guide(description: "Identify the dish first") var dish: DishIdentification
    @Guide(description: "The card title: the identified dish name as written") var title: String
    @Guide(description: "Under 20 words") var description: String
    @Guide(description: "Servings that suit the dish (stews 4 to 6)", .range(1...24)) var servings: Int
    @Guide(description: "Total minutes: prep plus the sum of all step times", .range(1...2880)) var timeMinutes: Int
    @Guide(description: "Short lowercase tags, include the dish type (main, side, dessert, drink)", .maximumCount(5)) var tags: [String]
    @Guide(description: "Ingredients for the identified dish, copied from the text when given; a main dish has at least 4 with amounts", .count(1...30)) var ingredients: [GenIngredient]
    @Guide(description: "Steps in order; timed steps carry minutes, oven steps carry temperatureC", .count(1...20)) var steps: [GenStep]
    @Guide(description: "Short note when the recipe is best-effort (advert/menu, unknown dish), otherwise empty") var note: String

    var card: RecipeCard {
        var c = baseCard
        c.aiConfidence = max(0, min(1, dish.confidence))
        let alts = dish.alternatives.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        c.aiAlternatives = alts.isEmpty ? nil : alts
        if title.trimmingCharacters(in: .whitespaces).isEmpty { c.title = dish.name }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        c.aiNote = n.isEmpty ? nil : n
        let stepMin = steps.compactMap(\.minutes).reduce(0, +)
        if stepMin > (c.timeMinutes ?? 0) { c.timeMinutes = stepMin }
        return c
    }

    /// Rendered straight from the structured fields (no text parsing). temperatureC is folded into the instruction
    /// only when the model didn't already write a temperature, so the card always shows it.
    var baseCard: RecipeCard {
        let cu = dish.cuisine.trimmingCharacters(in: .whitespaces)
        return RecipeCard(title: title, description: description, servings: max(1, servings),
                   timeMinutes: timeMinutes > 0 ? timeMinutes : nil, tags: tags,
                   ingredients: ingredients.map { Ingredient(name: $0.name, quantity: $0.quantity, unit: $0.unit, notes: $0.prep) },
                   steps: steps.enumerated().map { i, s in
                       Step(order: i + 1, instruction: GenRecipe.instruction(s.instruction, temperatureC: s.temperatureC),
                            timeSeconds: (s.minutes ?? 0) > 0 ? s.minutes! * 60 : nil) },
                   cuisine: cu.isEmpty ? nil : cu)
    }

    /// One-shot example for the Prompt (format only; the prompt says not to copy its content).
    static let exampleMogodu = GenRecipe(
        dish: DishIdentification(name: "Mogodu", cuisine: "South African", confidence: 0.95, alternatives: ["Ulusu"]),
        title: "Mogodu", description: "Slow-simmered beef tripe with onion and curry, served with pap.",
        servings: 6, timeMinutes: 200, tags: ["main", "south african", "slow cook"],
        ingredients: [GenIngredient(quantity: 1.5, unit: "kg", name: "beef tripe", prep: "cleaned and cut into strips"),
                      GenIngredient(quantity: 2, unit: "pcs", name: "onions", prep: "chopped"),
                      GenIngredient(quantity: 3, unit: "cloves", name: "garlic", prep: "crushed"),
                      GenIngredient(quantity: 2, unit: "tsp", name: "curry powder", prep: nil),
                      GenIngredient(quantity: 500, unit: "ml", name: "beef stock", prep: nil)],
        steps: [GenStep(instruction: "Cover the tripe with salted water and simmer, covered, until tender", minutes: 150, temperatureC: nil),
                GenStep(instruction: "Fry the onion and garlic in oil over medium heat until golden", minutes: 8, temperatureC: nil),
                GenStep(instruction: "Stir in the curry powder, tripe and stock and simmer until thick", minutes: 30, temperatureC: nil)],
        note: "")

    static func instruction(_ text: String, temperatureC: Int?) -> String {
        guard let t = temperatureC, !RecipeQuality.hasTemperature(text) else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        return body + " at \(t)°C."
    }
}

@available(iOS 26.0, *)
extension RecipeStreamPreview {
    init(_ p: GenRecipe.PartiallyGenerated) {
        self.init(title: p.title ?? p.dish?.name,
                  cuisine: p.dish?.cuisine,
                  confidence: p.dish?.confidence,
                  ingredients: (p.ingredients ?? []).compactMap { i in
                      guard let n = i.name, !n.isEmpty else { return nil }
                      return [i.quantity.map { RecipeLogic.round2($0) == $0.rounded() ? String(Int($0)) : String($0) }, i.unit, n]
                          .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                  },
                  steps: (p.steps ?? []).compactMap { $0.instruction }.filter { !$0.isEmpty })
    }
}

@available(iOS 26.0, *)
extension GenerationFailure {
    init(_ e: LanguageModelSession.GenerationError) {
        switch e {
        case .exceededContextWindowSize: self = .tooLong
        case .assetsUnavailable: self = .assetsUnavailable
        case .guardrailViolation: self = .guardrail
        case .unsupportedGuide: self = .unsupportedGuide
        case .unsupportedLanguageOrLocale: self = .language
        case .decodingFailure: self = .decoding
        case .rateLimited: self = .rateLimited
        default: self = .other
        }
    }
}
#endif
