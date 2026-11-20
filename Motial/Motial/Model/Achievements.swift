import Foundation

/// Milestones that celebrate real clinical progress (not just time spent), shown as badges.
/// Each one maps to something that matters for recovery: consistency, balance, strength, stage changes.
enum Badge: String, CaseIterable, Identifiable, Codable {
    case firstSession, threeDayStreak, sevenDayStreak, eightWeeks
    case steady20, steady30, heelRaises25, stageUp, firstGame, catchPro, riverCrossed, painFreeWeek

    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstSession: return "First Step"
        case .threeDayStreak: return "3-Day Streak"
        case .sevenDayStreak: return "7-Day Streak"
        case .eightWeeks: return "8-Week Finisher"
        case .steady20: return "20 Seconds Steady"
        case .steady30: return "30 Seconds Steady"
        case .heelRaises25: return "25 Heel Raises"
        case .stageUp: return "New Stage"
        case .firstGame: return "Player One"
        case .catchPro: return "Safe Hands"
        case .riverCrossed: return "River Crosser"
        case .painFreeWeek: return "Pain-Free Week"
        }
    }
    var detail: String {
        switch self {
        case .firstSession: return "Completed your first guided session."
        case .threeDayStreak: return "Trained 3 days in a row."
        case .sevenDayStreak: return "Trained 7 days in a row."
        case .eightWeeks: return "Kept balance training going for 8 weeks, the dose that prevents re-sprains."
        case .steady20: return "Held a one-leg stand for 20 seconds."
        case .steady30: return "Held a steady one-leg stand for 30 seconds."
        case .heelRaises25: return "25 single-leg heel raises: a return-to-run benchmark."
        case .stageUp: return "Moved up a rehab stage."
        case .firstGame: return "Played your first therapy game."
        case .catchPro: return "Caught 8 balls on one leg in a session."
        case .riverCrossed: return "Crossed the river on the stepping stones."
        case .painFreeWeek: return "A week of check-ins at 0–1/10 pain."
        }
    }
    var symbol: String {
        switch self {
        case .firstSession: return "figure.walk"
        case .threeDayStreak: return "flame"
        case .sevenDayStreak: return "flame.fill"
        case .eightWeeks: return "rosette"
        case .steady20: return "timer"
        case .steady30: return "figure.mind.and.body"
        case .heelRaises25: return "arrow.up.circle.fill"
        case .stageUp: return "stairs"
        case .firstGame: return "gamecontroller.fill"
        case .catchPro: return "baseball.fill"
        case .riverCrossed: return "water.waves"
        case .painFreeWeek: return "sun.max.fill"
        }
    }

    /// Badges the stored history has earned.
    static func earned(_ s: StoredState) -> Set<Badge> {
        var out = Set<Badge>()
        let sessions = s.sessions
        let results = sessions.flatMap(\.results)
        if !sessions.isEmpty { out.insert(.firstSession) }
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for d in days {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run); prev = d
        }
        if best >= 3 { out.insert(.threeDayStreak) }
        if best >= 7 { out.insert(.sevenDayStreak) }
        if let first = sessions.first?.date, let last = sessions.last?.date,
           (cal.dateComponents([.day], from: first, to: last).day ?? 0) >= 56, sessions.count >= 16 { out.insert(.eightWeeks) }
        let bestHold = results.map(\.bestHold).max() ?? 0
        if bestHold >= 20 { out.insert(.steady20) }
        if bestHold >= 30 && (results.compactMap(\.steadiness).max() ?? 0) >= 65 { out.insert(.steady30) }
        if (results.filter { $0.exerciseID == "sl_calf_raise" }.map(\.reps).max() ?? 0) >= 25 { out.insert(.heelRaises25) }
        if s.stageHistory.count >= 2 { out.insert(.stageUp) }
        let games: Set<String> = ["single_leg_stance", "sls_reach_catch", "stepping_stones", "rhythm_steps", "river_hops", "lantern_glide", "lantern_glide_seated", "dawn_drive", "dawn_drive_seated", "dawn_drive_cockpit"]
        if results.contains(where: { games.contains($0.exerciseID) && !$0.skipped }) { out.insert(.firstGame) }
        if results.contains(where: { $0.exerciseID == "sls_reach_catch" && ($0.gameScore ?? 0) >= 8 }) { out.insert(.catchPro) }
        if results.contains(where: { ($0.exerciseID == "stepping_stones" || $0.exerciseID == "river_hops") && ($0.gameScore ?? 0) > 0 }) { out.insert(.riverCrossed) }
        let recent = s.checkIns.suffix(7)
        if recent.count >= 7 && recent.allSatisfy({ $0.painRest <= 1 }) { out.insert(.painFreeWeek) }
        return out
    }
}
