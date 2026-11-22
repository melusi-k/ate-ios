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
        await CookPlanNotificationRemoval.perform(ids: ids) { ids in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
    func removeAllDelivered() async {
        let delivered = await center.deliveredNotifications()
        let ids = delivered.map { $0.request.identifier }
            .filter { $0.hasPrefix(CookPlan.reminderPrefix) }
        await CookPlanNotificationRemoval.perform(ids: ids) { ids in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}

/// Synchronous notification removal may block in XPC. Keep it off Main while
/// awaiting its return so the existing intent queue and verification stay ordered.
enum CookPlanNotificationRemoval {
    static func perform(ids: [String], operation: @escaping @Sendable ([String]) -> Void) async {
        guard !ids.isEmpty else { return }
        CookPlanCancelDiagnostic.mark("removal-continuation-before")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CookPlanCancelDiagnostic.mark("utility-dispatch-before")
            DispatchQueue.global(qos: .utility).async {
                CookPlanCancelDiagnostic.mark("utility-enter")
                operation(ids)
                CookPlanCancelDiagnostic.mark("utility-operation-return")
                continuation.resume()
            }
        }
        CookPlanCancelDiagnostic.mark("removal-continuation-return")
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
    private func enqueue(_ work: @escaping @MainActor (Int) async throws -> Void) -> Task<Void, Error> {
        generation += 1
        let token = generation
        let previous = tail
        CookPlanCancelDiagnostic.mark("queue-register", generation: token)
        let task = Task { @MainActor in
            CookPlanCancelDiagnostic.mark("queue-task-enter", generation: token)
            defer {
                CookPlanCancelDiagnostic.mark("queue-task-return", generation: token)
                if token == self.generation { self.tail = nil }
            }
            CookPlanCancelDiagnostic.mark("queue-predecessor-before", generation: token)
            _ = try? await previous?.value
            CookPlanCancelDiagnostic.mark("queue-predecessor-after", generation: token)
            CookPlanCancelDiagnostic.mark("queue-work-before", generation: token)
            try await work(token)
            CookPlanCancelDiagnostic.mark("queue-work-after", generation: token)
        }
        tail = task
        return task
    }

    /// Saving an OFF plan is local and synchronous. Register cleanup in the SAME
    /// ordered queue before returning, so a later re-enable cannot be cancelled by
    /// a task that only starts after the sheet is gone. Never claim OS removal yet.
    @discardableResult
    func saveWithoutReminder(_ plan: CookPlan, store: CookPlanStore,
                             onRemovalFailure: @escaping @MainActor () -> Void) throws -> Task<Void, Never> {
        guard !plan.reminderRequested else { throw CookPlanError.invalidPlan }
        CookPlanCancelDiagnostic.mark("off-save-local-before")
        try store.save(plan)
        CookPlanCancelDiagnostic.mark("off-save-local-after")
        let removal = enqueue { _ in try await self.removeAndVerify(recipeID: plan.recipeID) }
        CookPlanCancelDiagnostic.mark("off-save-cleanup-registered")
        return Task { @MainActor in
            CookPlanCancelDiagnostic.mark("off-save-cleanup-await")
            do {
                try await removal.value
                CookPlanCancelDiagnostic.mark("off-save-cleanup-return")
            }
            catch {
                CookPlanCancelDiagnostic.mark("off-save-cleanup-catch")
                onRemovalFailure()
            }
        }
    }

    private func removeAndVerify(recipeID: String) async throws {
        let ids = [CookPlan.reminderID(recipeID: recipeID)]
        CookPlanCancelDiagnostic.mark("remove-before")
        await client.remove(ids)
        CookPlanCancelDiagnostic.mark("remove-after")
        CookPlanCancelDiagnostic.mark("pending-ids-before")
        let remaining = await client.pendingIDs()
        CookPlanCancelDiagnostic.mark("pending-ids-after")
        guard remaining.isDisjoint(with: ids) else {
            CookPlanCancelDiagnostic.mark("verify-failed")
            throw CookPlanError.verificationFailed
        }
        CookPlanCancelDiagnostic.mark("verify-passed")
    }

    func reconcile(plans: [CookPlan], recipes: [RecipeCard], now: Date = Date()) async throws {
        try await enqueue { token in
            let allowed = await self.client.allowed(request: false)
            let pending = await self.client.pendingIDs()
            guard token == self.generation else { return }
            let state = CookPlanReminders.reconcile(plans: plans, existingRecipeIDs: Set(recipes.map(\.id)),
                notificationsAllowed: allowed, pendingIDs: pending, now: now)
            await self.client.remove(state.removeIDs)
            if !state.removeIDs.isEmpty {
                let remaining = await self.client.pendingIDs()
                guard token == self.generation else { return }
                guard remaining.isDisjoint(with: state.removeIDs) else {
                    throw CookPlanError.verificationFailed
                }
            }
            for plan in state.desired {
                guard token == self.generation, plan.scheduledAt > Date(),
                      let recipe = recipes.first(where: { $0.id == plan.recipeID }) else { return }
                try await self.client.add(plan, title: recipe.title)
                if token != self.generation {
                    await self.client.remove([plan.reminderID])
                    return
                }
            }
        }.value
    }

    func cancel(recipeID: String) async throws {
        try await enqueue { _ in try await self.removeAndVerify(recipeID: recipeID) }.value
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
        }.value
    }
}

/// Fixed QA-only phase evidence. No IDs, content, waits, timers or model reads.
enum CookPlanCancelDiagnostic {
    static func mark(_ phase: String, generation: Int = -1) {
        #if DEBUG
        guard AppConfig.isUITesting,
              ProcessInfo.processInfo.arguments.contains("-qaCookPlanCancelDiagnostic") else { return }
        let line = "COOK-PLAN-CANCEL phase=\(phase) generation=\(generation) monotonic_ns=\(DispatchTime.now().uptimeNanoseconds) main_thread=\(Thread.isMainThread)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        #endif
    }
}
