import Foundation

/// Pure rules: Health summary → body state + reasons. No I/O, fully unit-tested.
enum HealthInsightEngine {
    static let shortSleep = 6.5, goodSleep = 7.5
    static let hardWorkoutMinutes = 45.0, hardWorkoutKcal = 650.0
    static let lowSteps = 4000, activeSteps = 9000

    static func insight(for s: HealthSummary) -> HealthInsight? {
        guard s.hasAnyData, let today = s.today else { return nil }
        let recent = Array(s.days.suffix(2))
        let sleep = today.sleepHours
        let hardWorkout = recent.contains { ($0.workoutMinutes ?? 0) >= hardWorkoutMinutes || ($0.activeEnergyKcal ?? 0) >= hardWorkoutKcal }
        let lowDays = s.days.suffix(3).filter { ($0.steps ?? Int.max) < lowSteps }.count
        var reasons: [String] = []
        if let sleep { reasons.append("You slept \(fmt(sleep)) hours") }
        if let w = recent.compactMap(\.workoutMinutes).max(), w > 0 {
            let type = recent.flatMap(\.workoutTypes).first.map { " \($0.lowercased())" } ?? " workout"
            reasons.append("a \(Int(w))-minute\(type)")
        }
        if let avg = s.averageSteps { reasons.append("about \(avg.formatted()) steps a day") }

        let state: HealthState
        if hardWorkout { state = .recovery }
        else if s.days.count >= 3 && lowDays >= 3 { state = .underactive }
        else if let sleep, sleep < shortSleep { state = .lowEnergy }
        else if (today.steps ?? 0) < lowSteps && sleep == nil && today.steps != nil { state = .lowEnergy }
        else if let sleep, sleep >= goodSleep, (s.averageSteps ?? 0) >= activeSteps || (today.activeEnergyKcal ?? 0) >= 400 { state = .performance }
        else { state = .balanced }
        return HealthInsight(state: state, reasons: reasons, headline: headline(state, reasons))
    }

    static func headline(_ state: HealthState, _ reasons: [String]) -> String {
        let lead = reasons.isEmpty ? "" : reasons.prefix(2).joined(separator: " and ") + ". "
        switch state {
        case .recovery: return lead + "Favour protein-rich recovery meals today."
        case .lowEnergy: return lead + "Go for something lighter and comforting."
        case .performance: return lead + "A good day to cook something fresh or prep ahead."
        case .underactive: return lead + "A lighter dinner and a short walk could feel good."
        case .balanced: return lead + "Nothing stands out. Cook what you fancy."
        }
    }

    static func fmt(_ h: Double) -> String { h.truncatingRemainder(dividingBy: 1) < 0.25 ? "\(Int(h))" : String(format: "%.1f", h) }
}
