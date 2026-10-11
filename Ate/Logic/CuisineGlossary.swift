import Foundation

/// Regional dishes the on-device model often gets wrong. Used to (a) spot named dishes in captions/photos/hints and
/// (b) ground the prompt with typical ingredients and realistic times.
struct GlossaryDish: Equatable {
    let name: String
    let aliases: [String]
    let region: String
    let ingredients: String
    let minutes: Int
    let servings: Int
    let note: String
}

enum CuisineGlossary {
    static let dishes: [GlossaryDish] = [
        .init(name: "Pap", aliases: ["pap", "phutu", "putu", "uphuthu", "stywe pap", "krummelpap", "mieliepap", "bogobe"], region: "South African",
              ingredients: "white maize meal, water, salt (phutu: crumbly; stywe: stiff)", minutes: 30, servings: 4, note: "stir often, cover and steam 20 min"),
        .init(name: "Ujeqe (steamed bread)", aliases: ["ujeqe", "dombolo", "steamed bread", "idombolo"], region: "South African",
              ingredients: "cake flour, instant yeast, sugar, salt, warm water", minutes: 75, servings: 6, note: "prove about 40 min, steam 1 h or more"),
        .init(name: "Mogodu / ulusu (tripe)", aliases: ["mogodu", "ulusu", "mala mogodu", "mala", "tripe", "matumbu", "serobe"], region: "South African",
              ingredients: "beef tripe (and mala), onion, garlic, curry powder or stock, salt, pepper", minutes: 180, servings: 6, note: "clean well, simmer 2 to 3 h until tender"),
        .init(name: "Amanqina (chicken feet)", aliases: ["amanqina", "chicken feet", "walkie talkies", "maotwana"], region: "South African",
              ingredients: "chicken feet, onion, tomato, curry powder, paprika, garlic, stock", minutes: 90, servings: 4, note: "blanch and peel, braise about 1 h"),
        .init(name: "Morogo", aliases: ["morogo", "imifino", "muroho", "spinach morogo", "wild spinach"], region: "South African",
              ingredients: "morogo or spinach, onion, tomato, oil, salt (optional peanut)", minutes: 25, servings: 4, note: "wilt leaves, simmer until soft"),
        .init(name: "Chakalaka", aliases: ["chakalaka"], region: "South African",
              ingredients: "onion, peppers, carrots, baked beans, tomato, curry powder, chilli, garlic", minutes: 35, servings: 6, note: "spicy relish served with pap and braai"),
        .init(name: "Umngqusho (samp and beans)", aliases: ["umngqusho", "samp and beans", "samp", "isitambu"], region: "South African",
              ingredients: "samp, sugar beans, onion, butter, salt", minutes: 180, servings: 6, note: "soak overnight, simmer 2 to 3 h"),
        .init(name: "Chotlho", aliases: ["chotlo", "chotlho", "seswaa", "pounded beef"], region: "Botswana / Setswana",
              ingredients: "beef on the bone, salt, water", minutes: 180, servings: 6, note: "boil until falling apart, pound"),
        .init(name: "Beef stew", aliases: ["beef stew", "nyama", "inyama"], region: "South African",
              ingredients: "beef chuck or shin, onion, tomato, carrot, potato, curry powder or stock, garlic", minutes: 120, servings: 6, note: "brown, simmer 1.5 to 2 h"),
        .init(name: "Braai", aliases: ["braai", "shisa nyama", "chisa nyama", "tshisanyama"], region: "South African",
              ingredients: "boerewors, lamb chops or chicken, braai spice, pap, chakalaka", minutes: 60, servings: 6, note: "open-fire grilling"),
        .init(name: "Boerewors", aliases: ["boerewors", "wors"], region: "South African",
              ingredients: "boerewors coil, braai spice", minutes: 25, servings: 4, note: "grill over medium coals, don't prick"),
        .init(name: "Bobotie", aliases: ["bobotie"], region: "South African (Cape Malay)",
              ingredients: "beef mince, onion, curry powder, turmeric, chutney, bread, milk, eggs, bay leaves", minutes: 75, servings: 6, note: "bake with egg custard 35 to 40 min"),
        .init(name: "Potjiekos", aliases: ["potjiekos", "potjie"], region: "South African",
              ingredients: "lamb or beef, onion, potatoes, carrots, butternut, stock, spices", minutes: 180, servings: 6, note: "layered in a cast-iron pot, 3 h, don't stir"),
        .init(name: "Vetkoek / magwinya", aliases: ["vetkoek", "magwinya", "amagwinya", "fat cakes"], region: "South African",
              ingredients: "cake flour, yeast, sugar, salt, water, oil for frying", minutes: 90, servings: 8, note: "prove 1 h, deep-fry"),
        .init(name: "Kota", aliases: ["kota", "skhambane", "bunny chow", "sphatlho", "spatlo"], region: "South African",
              ingredients: "quarter white loaf, chips, polony, russian, cheese, atchar, egg", minutes: 30, servings: 1, note: "hollowed quarter loaf filled"),
        .init(name: "Spring rolls", aliases: ["spring roll", "spring rolls", "springroll", "springrolls"], region: "International / South African home cooking",
              ingredients: "spring-roll wrappers, cabbage or mixed vegetables, carrot, onion, garlic, ginger, soy sauce, oil for frying", minutes: 45, servings: 4, note: "season and cool the filling, seal wrappers, fry until crisp"),
        .init(name: "Ting", aliases: ["ting", "setswana ting", "fermented sorghum"], region: "Botswana / Setswana",
              ingredients: "sorghum meal, water (fermented 1 to 2 days)", minutes: 30, servings: 4, note: "ferment, then cook like soft porridge"),
        .init(name: "Sadza", aliases: ["sadza", "nshima", "nsima", "ugali"], region: "Southern / East African",
              ingredients: "white maize meal, water", minutes: 25, servings: 4, note: "stiff maize porridge"),
        .init(name: "Jollof rice", aliases: ["jollof"], region: "West African",
              ingredients: "long-grain rice, tomato, red pepper, scotch bonnet, onion, tomato paste, stock, thyme, curry, bay", minutes: 75, servings: 6, note: "pepper base cooked down first"),
        .init(name: "Egusi soup", aliases: ["egusi"], region: "West African",
              ingredients: "ground egusi seeds, palm oil, beef or goat, stockfish, spinach or bitterleaf, pepper, onion, crayfish", minutes: 90, servings: 6, note: "serve with fufu or eba"),
        .init(name: "Fufu", aliases: ["fufu", "foofoo", "eba", "pounded yam"], region: "West African",
              ingredients: "cassava and/or plantain (or yam / garri)", minutes: 45, servings: 4, note: "boil and pound or stir to a smooth dough"),
        .init(name: "Pap and braai meat", aliases: ["pap and vleis", "pap en vleis", "pap and meat", "mealie meal and braai"], region: "South African",
              ingredients: "maize meal, braai meat, chakalaka or tomato relish", minutes: 60, servings: 6, note: "classic plate"),
    ]

    /// Dishes whose name or alias appears as a whole word in the text.
    static func matches(in text: String) -> [GlossaryDish] {
        let t = " " + text.lowercased().replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression) + " "
        return dishes.filter { d in d.aliases.contains { t.contains(" " + $0 + " ") } }
    }

    static func promptLines(_ ds: [GlossaryDish]) -> String {
        ds.map { "- \($0.name) (\($0.region)): \($0.ingredients); about \($0.minutes) min total, serves \($0.servings); \($0.note)." }
            .joined(separator: "\n")
    }

    /// Suggestions offered on an uncertain food photo.
    static let photoSuggestions = ["Mogodu (tripe)", "Ujeqe (steamed bread)", "Amanqina (chicken feet)", "Beef stew", "Morogo",
                                   "Chakalaka", "Pap", "Umngqusho (samp and beans)"]
}
