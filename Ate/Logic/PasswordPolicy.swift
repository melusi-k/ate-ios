import Foundation

/// Client-side password rules, matching the Supabase project policy (min 8, letters + digits).
enum PasswordPolicy {
    static let minLength = 8
    static let common: Set<String> = ["password", "password1", "password12", "password123", "12345678", "123456789", "1234567890",
        "qwerty123", "qwertyuiop", "abc12345", "abcd1234", "iloveyou1", "letmein1", "welcome1", "admin123", "11111111",
        "00000000", "passw0rd", "p@ssw0rd", "football1", "monkey123", "dragon123", "sunshine1", "princess1", "qwerty12"]

    struct Result: Equatable {
        var problems: [String]
        var strength: Int          // 0…4
        var ok: Bool { problems.isEmpty }
        var label: String { ["Too weak", "Weak", "Fair", "Good", "Strong"][max(0, min(4, strength))] }
    }

    static func evaluate(_ p: String) -> Result {
        var problems: [String] = []
        let hasLetter = p.contains { $0.isLetter }, hasDigit = p.contains { $0.isNumber }
        if p.count < minLength { problems.append("At least \(minLength) characters") }
        if !hasLetter || !hasDigit { problems.append("Use a letter and a number") }
        if common.contains(p.lowercased()) { problems.append("That password is too common") }
        var s = 0
        if p.count >= minLength { s += 1 }
        if p.count >= 12 { s += 1 }
        if hasLetter && hasDigit { s += 1 }
        if p.contains(where: { !$0.isLetter && !$0.isNumber }) || (p.contains { $0.isUppercase } && p.contains { $0.isLowercase }) { s += 1 }
        if !problems.isEmpty { s = min(s, 1) }
        return Result(problems: problems, strength: s)
    }
}

/// Remembers when auth emails were last sent so the UI can show an honest cooldown.
/// Supabase's built-in mailer allows only a few emails per hour per project until custom SMTP is set up (docs/SMTP.md).
enum EmailCooldown {
    enum Kind: String { case signup, reset, magic }
    static let normal: TimeInterval = 60
    static let rateLimited: TimeInterval = 3600
    private static func key(_ k: Kind) -> String { "ate.emailcooldown.\(k.rawValue)" }

    static func record(_ k: Kind, rateLimited limited: Bool = false, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.addingTimeInterval(limited ? rateLimited : normal).timeIntervalSince1970, forKey: key(k))
    }
    static func remaining(_ k: Kind, now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        let until = defaults.double(forKey: key(k))
        return max(0, Int(ceil(until - now.timeIntervalSince1970)))
    }
    static func label(_ seconds: Int) -> String {
        seconds >= 120 ? "in about \(Int(ceil(Double(seconds) / 60))) min" : "in \(seconds) s"
    }
}
