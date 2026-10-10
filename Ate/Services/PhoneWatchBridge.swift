import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// iPhone side of WatchConnectivity: hands the Supabase session to a paired watch and mirrors active cook timers.
/// The watch app is fully independent; this only saves typing a code on the wrist and mirrors live cooking.
@MainActor
final class PhoneWatchBridge: NSObject {
    static let shared = PhoneWatchBridge()
    private var last = WatchBridgePayload()

    func activate() {
        #if canImport(WatchConnectivity)
        guard !AppConfig.isUITesting, WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    func update(session s: AuthSession?) {
        last.session = s.map { .init(accessToken: $0.accessToken, refreshToken: $0.refreshToken, expiresAt: $0.expiresAt, userID: $0.userID, email: $0.email) }
        last.signedOut = s == nil
        push()
    }

    func update(timers: [ActiveTimer]) {
        last.cook = timers.map {
            .init(recipeID: $0.recipeID, recipeTitle: $0.recipeTitle, stepIndex: $0.stepIndex, stepCount: $0.stepCount,
                  stepText: $0.stepText, timerEnd: $0.endDate, timerRemaining: $0.remaining())
        }
        push()
    }

    private func push() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        last.sentAt = Date()
        let dict = last.dictionary()
        try? WCSession.default.updateApplicationContext(dict)
        if WCSession.default.isReachable { WCSession.default.sendMessage(dict, replyHandler: nil) }
        #endif
    }
}

#if canImport(WatchConnectivity)
extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
