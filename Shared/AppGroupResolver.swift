import Foundation

/// Resolves the App Group actually granted to this signed bundle at runtime.
/// Sideloaders re-sign with their own team and may rename the group
/// (AltStore/SideStore: `group.com.melusik.ate.<TEAMID>`), so the hard-coded id is only a fallback.
/// Order: embedded.mobileprovision entitlements → Info.plist `ALTAppGroups` → default → `group.<app bundle id>`.
/// Each candidate is only accepted if iOS hands back a container for it.
enum AppGroupResolver {
    static let defaultID = "group.com.melusik.ate"

    struct Resolution: Equatable { var id: String; var source: String; var available: Bool }

    static let current: Resolution = resolve(bundle: .main) {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }

    static func resolve(bundle: Bundle, isUsable: (String) -> Bool) -> Resolution {
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }.map(profileGroups) ?? []
        let alt = (bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        let derived = bundle.bundleIdentifier.map { "group." + appBundleID($0) }
        return resolve(profile: profile, alt: alt, derived: derived, isUsable: isUsable)
    }

    static func resolve(profile: [String], alt: [String], derived: String?, isUsable: (String) -> Bool) -> Resolution {
        var seen = Set<String>()
        var cands: [(String, String)] = []
        func add(_ ids: [String], _ src: String) {
            for id in ranked(ids) where !id.contains("*") && seen.insert(id).inserted { cands.append((id, src)) }
        }
        add(profile, "profile"); add(alt, "Info.plist"); add([defaultID], "default")
        if let d = derived { add([d], "bundle id") }
        for (id, src) in cands where isUsable(id) { return Resolution(id: id, source: src, available: true) }
        return Resolution(id: cands.first?.0 ?? defaultID, source: cands.first?.1 ?? "default", available: false)
    }

    /// Groups that look like ate's come first (e.g. `group.com.melusik.ate.ABC123`).
    static func ranked(_ ids: [String]) -> [String] {
        ids.filter { $0.hasPrefix("group.") }.sorted { score($0) > score($1) }
    }
    private static func score(_ id: String) -> Int {
        id == defaultID ? 3 : id.hasPrefix(defaultID) ? 2 : id.lowercased().contains("melusik") ? 1 : 0
    }

    /// `com.x.ate.TEAM.widgets` → `com.x.ate.TEAM` for extensions; the app's own id is unchanged.
    static func appBundleID(_ id: String) -> String {
        let ext = ["widgets", "share", "watchkitapp", "watchwidgets"]
        let parts = id.split(separator: ".")
        if let last = parts.last, ext.contains(last.lowercased()), parts.count > 1 { return parts.dropLast().joined(separator: ".") }
        return id
    }

    /// Reads `Entitlements → com.apple.security.application-groups` from a CMS-wrapped provisioning profile.
    static func profileGroups(_ data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any] else { return [] }
        return ent["com.apple.security.application-groups"] as? [String] ?? []
    }
}
