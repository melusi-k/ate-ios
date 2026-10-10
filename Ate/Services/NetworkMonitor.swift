import Foundation
import Network
import Observation

/// Reachability for offline UI. `-simulateOffline` forces offline (UI tests).
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        if ProcessInfo.processInfo.arguments.contains("-simulateOffline") { isOnline = false; return }
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "ate.network"))
    }
}
