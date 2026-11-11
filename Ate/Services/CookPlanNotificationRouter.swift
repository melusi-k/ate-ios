import Foundation
import UserNotifications

/// Retain a tap received before SwiftUI's root has subscribed. Only this feature's
/// request namespace is accepted; timer notifications keep their existing behavior.
final class CookPlanNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CookPlanNotificationRouter()
    static let tapped = Notification.Name("ate.cookPlanNotificationTapped")
    private var pendingID: String?
    private let lock = NSLock()

    func takePendingRecipeID() -> String? {
        lock.lock(); defer { lock.unlock() }
        let id = pendingID
        pendingID = nil
        return id
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = CookPlanNotificationRoute.recipeID(requestID: request.identifier,
                  payloadRecipeID: request.content.userInfo["cookPlanRecipeID"] as? String) else {
            completionHandler(); return
        }
        lock.lock(); pendingID = id; lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.tapped, object: nil) }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier.hasPrefix(CookPlan.reminderPrefix) ? [.banner, .sound] : [])
    }
}
