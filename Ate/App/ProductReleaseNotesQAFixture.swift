#if DEBUG
import Foundation

/// Only the explicit release-history journey pins catalog visibility to its
/// asserted build. Installed app identity and production filtering stay real.
enum ProductReleaseNotesQAFixture {
    static func buildNumber(actual: Int, isUITesting: Bool, arguments: [String]) -> Int {
        guard isUITesting, arguments.contains("-qaReleaseHistory445") else { return actual }
        return 445
    }
}
#endif
