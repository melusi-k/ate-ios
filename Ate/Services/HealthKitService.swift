import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

enum HealthAccess: Equatable {
    case unavailable          // device has no Health (iPad, some simulators)
    case entitlementMissing   // sideload re-signed without com.apple.developer.healthkit
    case notDetermined
    case requested            // asked; HealthKit never tells read-apps if they were denied
    case denied
}

/// Read-only Health access. Live implementation + mock (UI tests / simulator demo).
protocol HealthKitServicing {
    var access: HealthAccess { get }
    /// Asks only for the MVP read types (sleep, steps, active energy, workouts). Never writes.
    func requestAccess() async -> HealthAccess
    func summary(days: Int) async -> HealthSummary
}

enum HealthServiceFactory {
    static let scenarios = ["recovery", "lowEnergy", "performance", "underactive", "empty", "denied", "unavailable", "noEntitlement"]
    /// Beta testing → Health insights debug picker ("" = real Apple Health).
    static let debugKey = "ate.health.mockScenario"
    /// `-qaMockHealth <scenario>` wins; otherwise the beta debug picker; otherwise live HealthKit.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) -> HealthKitServicing {
        if let i = arguments.firstIndex(of: "-qaMockHealth") {
            let s = i + 1 < arguments.count ? arguments[i + 1] : "recovery"
            return MockHealthKitService(scenario: s)
        }
        if !AppConfig.isUITesting, let s = defaults.string(forKey: debugKey), scenarios.contains(s) { return MockHealthKitService(scenario: s) }
        return LiveHealthKitService()
    }
}

final class MockHealthKitService: HealthKitServicing {
    let scenario: String
    private(set) var access: HealthAccess
    init(scenario: String) {
        self.scenario = scenario
        access = scenario == "unavailable" ? .unavailable : scenario == "noEntitlement" ? .entitlementMissing : .notDetermined
    }
    func requestAccess() async -> HealthAccess {
        if access == .unavailable || access == .entitlementMissing { return access }
        access = scenario == "denied" ? .denied : .requested
        return access
    }
    func summary(days: Int) async -> HealthSummary {
        guard access == .requested else { return HealthSummary(days: []) }
        return Self.fixture(scenario, days: days)
    }
    static func fixture(_ scenario: String, days: Int = 7, now: Date = .now) -> HealthSummary {
        let cal = Calendar.current
        func day(_ back: Int, sleep: Double?, steps: Int?, kcal: Double?, workout: Double? = nil, types: [String] = []) -> HealthDay {
            HealthDay(date: cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now))!, sleepHours: sleep, steps: steps,
                      activeEnergyKcal: kcal, workoutMinutes: workout, workoutTypes: types)
        }
        let n = max(1, min(days, 7))
        switch scenario {
        case "empty", "denied": return HealthSummary(days: [])
        case "lowEnergy": return HealthSummary(days: (0..<n).reversed().map { day($0, sleep: 5.4, steps: 5200, kcal: 180) })
        case "performance": return HealthSummary(days: (0..<n).reversed().map { day($0, sleep: 8.1, steps: 10500, kcal: 520, workout: $0 == 2 ? 25 : nil, types: $0 == 2 ? ["Cycling"] : []) })
        case "underactive": return HealthSummary(days: (0..<n).reversed().map { day($0, sleep: 7.2, steps: 2100, kcal: 120) })
        default: // recovery
            return HealthSummary(days: (0..<n).reversed().map { b in
                b == 1 ? day(b, sleep: 6.0, steps: 12400, kcal: 780, workout: 55, types: ["Running"])
                       : day(b, sleep: 6.0, steps: 8000, kcal: 400) })
        }
    }
}

final class LiveHealthKitService: HealthKitServicing {
    private(set) var access: HealthAccess = .notDetermined
    private static let askedKey = "ate.health.asked.v1"

    /// True when the running binary was signed with the HealthKit entitlement. Sideloaded builds re-signed
    /// without it can never reach Health, so the UI says so instead of pointing at Settings.
    static var hasEntitlement: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1) else { return true } // no profile = App Store / simulator
        return raw.contains("com.apple.developer.healthkit")
    }

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    static var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
    }
    #endif

    init() {
        #if canImport(HealthKit)
        if !HKHealthStore.isHealthDataAvailable() { access = .unavailable }
        else if !Self.hasEntitlement { access = .entitlementMissing }
        else if UserDefaults.standard.bool(forKey: Self.askedKey) { access = .requested }
        #else
        access = .unavailable
        #endif
    }

    func requestAccess() async -> HealthAccess {
        #if canImport(HealthKit)
        guard access == .notDetermined || access == .requested else { return access }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            access = .requested
        } catch {
            let msg = String(describing: error).lowercased()
            access = msg.contains("entitlement") || msg.contains("application-identifier") ? .entitlementMissing : .denied
        }
        #endif
        return access
    }

    func summary(days: Int) async -> HealthSummary {
        #if canImport(HealthKit)
        guard access == .requested else { return HealthSummary(days: []) }
        let cal = Calendar.current
        let n = max(1, min(days, 7))
        var out: [HealthDay] = []
        for back in (0..<n).reversed() {
            let start = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: .now))!
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            async let steps = sum(.stepCount, .count(), start, end)
            async let kcal = sum(.activeEnergyBurned, .kilocalorie(), start, end)
            async let sleep = sleepHours(endingIn: start, end)
            async let w = workouts(start, end)
            let (s, k, sl, wo) = await (steps, kcal, sleep, w)
            out.append(HealthDay(date: start, sleepHours: sl, steps: s.map { Int($0) }, activeEnergyKcal: k,
                                 workoutMinutes: wo.isEmpty ? nil : wo.reduce(0) { $0 + $1.duration } / 60,
                                 workoutTypes: wo.map { $0.workoutActivityType.ateName }))
        }
        return HealthSummary(days: out)
        #else
        return HealthSummary(days: [])
        #endif
    }

    #if canImport(HealthKit)
    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ s: Date, _ e: Date) async -> Double? {
        let pred = HKQuery.predicateForSamples(withStart: s, end: e)
        let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: pred), options: .cumulativeSum)
        guard let v = try? await d.result(for: store)?.sumQuantity()?.doubleValue(for: unit), v > 0 else { return nil }
        return v
    }
    /// Sleep for the night ending on this day (6pm previous day → noon).
    private func sleepHours(endingIn dayStart: Date, _ dayEnd: Date) async -> Double? {
        let s = dayStart.addingTimeInterval(-6 * 3600), e = dayStart.addingTimeInterval(12 * 3600)
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                                                     predicate: HKQuery.predicateForSamples(withStart: s, end: e))],
                                        sortDescriptors: [])
        guard let samples = try? await d.result(for: store) else { return nil }
        let secs = samples.filter { asleep.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return secs > 0 ? secs / 3600 : nil
    }
    private func workouts(_ s: Date, _ e: Date) async -> [HKWorkout] {
        let d = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: s, end: e))], sortDescriptors: [])
        return (try? await d.result(for: store)) ?? []
    }
    #endif
}

#if canImport(HealthKit)
extension HKWorkoutActivityType {
    var ateName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .soccer: return "Football"
        default: return "Workout"
        }
    }
}
#endif
