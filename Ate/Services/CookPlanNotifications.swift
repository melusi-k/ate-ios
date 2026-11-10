import Foundation
import UserNotifications

/// Injectable OS boundary for sequencing and fault-path tests without requesting permission.
@MainActor
protocol CookPlanNotificationClient {
    func allowed(request: Bool) async -> Bool
    func pendingIDs() async -> Set<String>
    func add(_ plan: CookPlan, title: String) async throws
    func remove(_ ids: [String]) async
    func removeAllDelivered() async
}

@MainActor
final class SystemCookPlanNotificationClient: CookPlanNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func allowed(request: Bool) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined where request:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }
    func pendingIDs() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }
    func add(_ plan: CookPlan, title: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Time to cook"; content.body = title; content.sound = .default
        content.userInfo = ["cookPlanRecipeID": plan.recipeID]
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: plan.timeZoneID) else { throw CookPlanError.invalidPlan }
        calendar.timeZone = zone
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.scheduledAt)
        parts.timeZone = zone
        try await center.add(UNNotificationRequest(identifier: plan.reminderID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
    func remove(_ ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
    func removeAllDelivered() async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered.map { $0.request.identifier }
            .filter { $0.hasPrefix(CookPlan.reminderPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

@MainActor
final class CookPlanNotifications {
    enum Permission: Equatable { case allowed, denied }
    private let client: CookPlanNotificationClient
    private var tail: Task<Void, Error>?
    private var generation = 0
    init(client: CookPlanNotificationClient? = nil) { self.client = client ?? SystemCookPlanNotificationClient() }

    func permission(requestIfNeeded: Bool) async -> Permission {
        await client.allowed(request: requestIfNeeded) ? .allowed : .denied
    }

    /// Every new intent invalidates older adds, including an add suspended inside the OS.
    /// Queue ordering then ensures cleanup completes after that add before returning success.
    private func enqueue(_ work: @escaping @MainActor (Int) async throws -> Void) async throws {
        generation += 1
        let token = generation
        let previous = tail
        let task = Task { @MainActor in
            _ = try? await previous?.value
            try await work(token)
        }
        tail = task
        do {
            try await task.value
            if token == generation { tail = nil }
        } catch {
            if token == generation { tail = nil }
            throw error
        }
    }

    func reconcile(plans: [CookPlan], recipes: [RecipeCard], now: Date = Date()) async throws {
        try await enqueue { token in
            let allowed = await self.client.allowed(request: false)
            let pending = await self.client.pendingIDs()
            guard token == self.generation else { return }
            let state = CookPlanReminders.reconcile(plans: plans, existingRecipeIDs: Set(recipes.map(\.id)),
                notificationsAllowed: allowed, pendingIDs: pending, now: now)
            await self.client.remove(state.removeIDs)
            for plan in state.desired {
                guard token == self.generation, plan.scheduledAt > Date(),
                      let recipe = recipes.first(where: { $0.id == plan.recipeID }) else { return }
                try await self.client.add(plan, title: recipe.title)
                if token != self.generation {
                    await self.client.remove([plan.reminderID])
                    return
                }
            }
        }
    }

    func cancel(recipeID: String) async throws {
        try await enqueue { _ in
            let ids = [CookPlan.reminderID(recipeID: recipeID)]
            await self.client.remove(ids)
            let remaining = await self.client.pendingIDs()
            guard remaining.isDisjoint(with: ids) else { throw CookPlanError.verificationFailed }
        }
    }
    func cancelAll() async throws {
        try await enqueue { _ in
            let pending = await self.client.pendingIDs()
            let ids = pending.filter { $0.hasPrefix(CookPlan.reminderPrefix) }
            await self.client.remove(Array(ids))
            await self.client.removeAllDelivered()
            let remaining = await self.client.pendingIDs()
            guard remaining.allSatisfy({ !$0.hasPrefix(CookPlan.reminderPrefix) }) else {
                throw CookPlanError.verificationFailed
            }
        }
    }
}
