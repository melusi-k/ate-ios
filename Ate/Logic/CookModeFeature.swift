import Foundation

/// Presentation only. Does not own a session, timer, completion or microphone.
enum CookModeFeature {
    static var stitchCookModeEnabled: Bool {
        enabled(configured: Bundle.main.object(forInfoDictionaryKey: "StitchCookModeEnabled") as? Bool,
                isUITesting: AppConfig.isUITesting, arguments: ProcessInfo.processInfo.arguments)
    }
    static func enabled(configured: Bool?, isUITesting: Bool, arguments: [String]) -> Bool {
        if isUITesting && arguments.contains("-qaStitchCookModeOff") { return false }
        return configured ?? true
    }
}
