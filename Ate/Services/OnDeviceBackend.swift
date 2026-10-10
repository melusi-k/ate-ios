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
        if request.mode == .url {
            if let html = try? await Self.fetchHTML(request.text ?? "") {
                pageHTML = html
                if let card = JSONLD.recipe(fromHTML: html, sourceURL: request.text) { return RecipeLogic.normalize(card) }
            }
        }
        guard Self.isModelAvailable else { return try await fallback.parseRecipe(request) }
        let prompt: String
        switch request.mode {
        case .prompt:
            prompt = "Recipe card for: \(String((request.text ?? "").prefix(500)))"
        case .url:
            let page: String
            if let html = pageHTML { page = String(Self.htmlToText(html).prefix(3500)) }
            else { page = try await Self.fetchPageText(request.text ?? "") }
            prompt = "Extract the recipe from this web page text:\n\(page)"
        case .image:
            let text = try await Self.ocr(dataURL: request.imageDataUrl ?? "")
            guard !text.isEmpty else { throw BackendError(message: "Couldn't read any text in that screenshot.") }
            prompt = "Extract the recipe from this screenshot text:\n\(String(text.prefix(3500)))"
        case .rewrite:
            var c = request.currentRecipe ?? RecipeCard()
            c.imageURL = nil; c.sourceURL = nil
            let json = (try? String(data: JSONEncoder().encode(c), encoding: .utf8)) ?? ""
            prompt = "Rewrite per \"\(request.text ?? "")\":\n\(json)"
        }
        var card = try await Self.generate(prompt)
        if request.mode == .url { card.sourceURL = request.text }
        if request.mode == .rewrite, let cur = request.currentRecipe {
            card.id = cur.id; card.createdAt = cur.createdAt; card.imageURL = cur.imageURL; card.sourceURL = cur.sourceURL
        }
        return RecipeLogic.normalize(card)
    }

    func publish(_ card: RecipeCard) async throws -> String { try await sharing.publish(card) }
    func fetchShared(slug: String) async throws -> RecipeCard? {
        if slug == "demo" { return try await fallback.fetchShared(slug: slug) }
        return try await sharing.fetchShared(slug: slug)
    }

    static let instructions = """
    You are a recipe parser. Produce a clean recipe card. Numeric quantities, short units (g, ml, tbsp, tsp, cloves, pcs). \
    timeSeconds only for waiting/cooking steps, otherwise omit. Keep description under 20 words, steps concise. \
    If the input is not a recipe, invent a sensible recipe matching it.
    """

    static func generate(_ prompt: String) async throws -> RecipeCard {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            do {
                let res = try await session.respond(to: prompt, generating: GenRecipe.self)
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
        r.timeoutInterval = 8
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 ate/1.0", forHTTPHeaderField: "User-Agent")
        r.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, resp) = try await Net.data(for: r)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw BackendError(message: "That page didn't load (HTTP \(code)). Check the link and try again.")
        }
        return String(decoding: data.prefix(1_500_000), as: UTF8.self)
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
    @Guide(description: "Numeric quantity, 0 if unspecified") var quantity: Double
    @Guide(description: "Short unit like g, ml, tbsp, tsp, cloves, pcs, or empty") var unit: String
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
    var title: String
    @Guide(description: "Under 20 words") var description: String
    @Guide(description: "Number of servings, at least 1") var servings: Int
    @Guide(description: "Total time in minutes") var timeMinutes: Int
    @Guide(description: "Up to 5 short lowercase tags") var tags: [String]
    var ingredients: [GenIngredient]
    var steps: [GenStep]

    var card: RecipeCard {
        RecipeCard(title: title, description: description, servings: max(1, servings),
                   timeMinutes: timeMinutes > 0 ? timeMinutes : nil, tags: tags,
                   ingredients: ingredients.map { Ingredient(name: $0.name, quantity: $0.quantity, unit: $0.unit, notes: $0.notes) },
                   steps: steps.enumerated().map { Step(order: $0.offset + 1, instruction: $0.element.instruction,
                                                        timeSeconds: ($0.element.timeSeconds ?? 0) > 0 ? $0.element.timeSeconds : nil) })
    }
}
#endif
