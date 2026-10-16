import Foundation

struct ClipRecipe: Decodable {
    let title: String
    let description: String?
    let servings: Int?
    let timeMinutes: Int?
    let ingredients: [ClipIngredient]
    let steps: [ClipStep]
    enum CodingKeys: String, CodingKey { case title, description, servings, timeMinutes, ingredients, steps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)).flatMap { $0.isEmpty ? nil : $0 } ?? "Shared recipe"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        servings = try? c.decodeIfPresent(Int.self, forKey: .servings)
        timeMinutes = try? c.decodeIfPresent(Int.self, forKey: .timeMinutes)
        ingredients = (try? c.decode([ClipIngredient].self, forKey: .ingredients)) ?? []
        steps = (try? c.decode([ClipStep].self, forKey: .steps)) ?? []
    }
}
struct ClipIngredient: Decodable, Identifiable {
    let name: String
    let quantity: Double?
    let unit: String?
    let notes: String?
    var id: String { "\(name)-\(quantity ?? 0)-\(unit ?? "")" }
    enum CodingKeys: String, CodingKey { case name, quantity, unit, notes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Ingredient"
        quantity = try? c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }
}
struct ClipStep: Decodable, Identifiable {
    let order: Int
    let instruction: String
    var id: Int { order }
    enum CodingKeys: String, CodingKey { case order, instruction }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        instruction = (try? c.decode(String.self, forKey: .instruction)) ?? ""
    }
}
enum ClipLoadError: LocalizedError {
    case invalidURL, invalidResponse, notFound, server, malformedData
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "This recipe link is not valid."
        case .invalidResponse: return "The recipe service returned an unexpected response."
        case .notFound: return "This shared recipe may have expired or been removed."
        case .server: return "The recipe service is temporarily unavailable. Please try again."
        case .malformedData: return "This shared recipe could not be read."
        }
    }
}
struct SharedRecipeClient {
    let baseURL: URL
    let publishableKey: String
    var session: URLSession = .shared
    func fetch(slug: String) async throws -> ClipRecipe {
        guard slug.range(of: "^[a-zA-Z0-9]{4,40}$", options: .regularExpression) != nil,
              var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw ClipLoadError.invalidURL }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/functions/v1/get-shared-recipe"
        parts.queryItems = [URLQueryItem(name: "slug", value: slug)]
        guard let url = parts.url else { throw ClipLoadError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClipLoadError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 400, 404: throw ClipLoadError.notFound
        case 500...599: throw ClipLoadError.server
        default: throw ClipLoadError.invalidResponse
        }
        struct Envelope: Decodable { let card: ClipRecipe }
        do { return try JSONDecoder().decode(Envelope.self, from: data).card }
        catch { throw ClipLoadError.malformedData }
    }
}
