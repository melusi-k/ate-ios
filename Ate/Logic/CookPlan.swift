import Foundation

/// One local cooking occasion per saved recipe. The instant and the zone chosen at save
/// are explicit: travel does not silently move an already scheduled cooking reminder.
struct CookPlan: Codable, Equatable {
    let recipeID: String
    let scheduledAt: Date
    let timeZoneID: String
    let reminderRequested: Bool

    var isValid: Bool {
        !recipeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        scheduledAt.timeIntervalSince1970.isFinite && TimeZone(identifier: timeZoneID) != nil
    }

    /// An injective stable identifier. Re-saving or changing this recipe replaces its
    /// reminder; this namespace never overlaps the existing ate.timer.* notifications.
    var reminderID: String { Self.reminderID(recipeID: recipeID) }
    static let reminderPrefix = "ate.cook-plan."
    static func reminderID(recipeID: String) -> String {
        reminderPrefix + Data(recipeID.utf8).base64EncodedString()
    }
}

enum CookPlanError: Error, Equatable {
    case invalidPlan, pastDate, unreadable, verificationFailed
}

/// Small local repository. A failed/corrupt read is not an empty plan list, and writes
/// verify their bytes before returning success. No notification permission is needed here.
final class CookPlanStore {
    static let storageKey = "ate.cook-plans.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func plans() throws -> [CookPlan] {
        guard let raw = defaults.object(forKey: Self.storageKey) else { return [] }
        guard let data = raw as? Data,
              let plans = try? JSONDecoder().decode([CookPlan].self, from: data),
              plans.allSatisfy(\.isValid),
              Set(plans.map(\.recipeID)).count == plans.count else { throw CookPlanError.unreadable }
        return plans.sorted { $0.recipeID < $1.recipeID }
    }

    func save(_ plan: CookPlan, now: Date = Date()) throws {
        guard plan.isValid else { throw CookPlanError.invalidPlan }
        guard plan.scheduledAt > now else { throw CookPlanError.pastDate }
        var intended = try plans().filter { $0.recipeID != plan.recipeID }
        intended.append(plan)
        try write(intended)
    }

    func cancel(recipeID: String) throws {
        try write(plans().filter { $0.recipeID != recipeID })
    }

    func clear() throws { try write([]) }

    private func write(_ plans: [CookPlan]) throws {
        let intended = plans.sorted { $0.recipeID < $1.recipeID }
        let data = try JSONEncoder().encode(intended)
        defaults.set(data, forKey: Self.storageKey)
        guard defaults.data(forKey: Self.storageKey) == data,
              try self.plans() == intended else { throw CookPlanError.verificationFailed }
    }
}

/// Pure desired state for a later notification adapter. Denied permission suppresses
/// notifications, never the persisted plan. Unknown pending identifiers are left alone.
enum CookPlanReminders {
    struct Reconciliation: Equatable {
        let desired: [CookPlan]
        let removeIDs: [String]
    }

    static func reconcile(plans: [CookPlan], existingRecipeIDs: Set<String>,
                          notificationsAllowed: Bool, pendingIDs: Set<String>,
                          now: Date) -> Reconciliation {
        let desired = notificationsAllowed ? plans.filter {
            $0.isValid && $0.reminderRequested && $0.scheduledAt > now && existingRecipeIDs.contains($0.recipeID)
        }.sorted { $0.recipeID < $1.recipeID } : []
        let desiredIDs = Set(desired.map(\.reminderID))
        let removeIDs = pendingIDs.filter {
            $0.hasPrefix(CookPlan.reminderPrefix) && !desiredIDs.contains($0)
        }.sorted()
        // Adapter uses add(request) with reminderID, replacing the same pending request.
        return Reconciliation(desired: desired, removeIDs: removeIDs)
    }
}

/// Reject mismatched payloads rather than open a different recipe from a stale request.
enum CookPlanNotificationRoute {
    static func recipeID(requestID: String, payloadRecipeID: String?) -> String? {
        guard let id = payloadRecipeID, !id.isEmpty,
              requestID == CookPlan.reminderID(recipeID: id) else { return nil }
        return id
    }
}
