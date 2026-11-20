import SwiftUI
import Charts

/// "Your drives": every pedal-game run kept on this device. Personal bests, a trend of how many obstacles you
/// cleared smoothly, and the recent runs with time, orbs and obstacles. Control is celebrated, not speed.
struct GameRecordsCard: View {
    @State private var filter = "all"
    private var log: GameLog { GameLog.shared }

    private let filters: [(String, String)] = [("all", "All"), ("dawn_drive", "Dawn Drive"), ("dawn_drive_cockpit", "Cockpit"), ("lantern_glide", "Lantern Glide")]

    private var runs: [GameRecord] {
        log.records.filter { r in
            switch filter {
            case "all": return true
            case "dawn_drive": return r.exerciseID.hasPrefix("dawn_drive") && r.exerciseID != "dawn_drive_cockpit"
            case "lantern_glide": return r.exerciseID.hasPrefix("lantern_glide")
            default: return r.exerciseID == filter
            }
        }
    }

    var body: some View {
        Card {
            HStack {
                Label("Your drives", systemImage: "flag.checkered").font(.title2.bold())
                Spacer()
                Picker("Game", selection: $filter) {
                    ForEach(filters, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented).frame(width: 460)
            }
            if runs.isEmpty {
                ContentUnavailableView("No drives yet", systemImage: "steeringwheel",
                                       description: Text("Play Dawn Drive or Lantern Glide and your times, orbs and smooth corners appear here."))
                    .frame(height: 220)
            } else {
                bests
                trend
                recent
            }
        }
    }

    // MARK: Personal bests
    private var bests: some View {
        let total = runs.reduce(0.0) { $0 + $1.seconds }
        let cleared = runs.reduce(0) { $0 + $1.obstaclesCleared }
        let faced = runs.reduce(0) { $0 + $1.obstaclesTotal }
        let bestLap = runs.compactMap(\.bestLap).min()
        let mostOrbs = runs.map(\.orbs).max() ?? 0
        return HStack(spacing: 14) {
            tile("\(runs.count)", "runs", "flag.checkered")
            tile(Self.clock(total), "time driven", "timer")
            tile("\(cleared)/\(faced)", "obstacles smooth", "checkmark.seal.fill")
            tile(bestLap.map { String(format: "%.1f s", $0) } ?? "–", "best lap", "stopwatch.fill")
            tile("\(mostOrbs)", "most orbs", "sparkles")
        }
    }

    private func tile(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Trend: share of obstacles taken smoothly (ankle control)
    private struct Point: Identifiable { let id: UUID; let n: Int; let pct: Double; let game: String }
    private var trend: some View {
        let pts = runs.suffix(20).enumerated().map { i, r in
            Point(id: r.id, n: i + 1,
                  pct: r.obstaclesTotal > 0 ? Double(r.obstaclesCleared) / Double(r.obstaclesTotal) * 100 : r.smoothness * 100,
                  game: r.title)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Smooth control, run by run").font(.headline)
            Text("The share of corners, gates or lanterns you took smoothly. Rising bars mean better ankle control.")
                .font(.caption).foregroundStyle(.secondary)
            Chart(pts) { p in
                BarMark(x: .value("Run", p.n), y: .value("Smooth %", p.pct))
                    .foregroundStyle(by: .value("Game", p.game))
                    .cornerRadius(4)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .frame(height: 170)
        }
    }

    // MARK: Recent runs
    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent runs").font(.headline)
            ForEach(Array(runs.suffix(6).reversed())) { r in
                HStack(spacing: 14) {
                    Image(systemName: r.exerciseID.hasPrefix("lantern") ? "sailboat.fill" : (r.exerciseID.contains("cockpit") ? "steeringwheel" : "car.fill"))
                        .frame(width: 34, height: 34).background(Theme.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.subheadline.bold())
                        Text(r.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    stat(Self.clock(r.seconds), "time")
                    stat("\(r.obstaclesCleared)/\(r.obstaclesTotal)", r.obstacleName)
                    stat("\(r.orbs)", "orbs")
                    stat(r.bestLap.map { String(format: "%.1f", $0) } ?? "–", "best lap")
                    if r.completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
                }
                .padding(10)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.callout.bold()).monospacedDigit()
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 74)
    }

    static func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// One line for the get-ready screen: how the last run of this game went.
struct LastRunLine: View {
    let exerciseID: String
    var body: some View {
        if let r = GameLog.shared.records.last(where: { $0.exerciseID == exerciseID }) {
            Label("Last time \(r.date.formatted(.relative(presentation: .named))): \(r.obstaclesCleared)/\(r.obstaclesTotal) \(r.obstacleName) smooth · \(r.orbs) orbs · \(GameRecordsCard.clock(r.seconds))"
                  + (r.bestLap.map { String(format: " · best lap %.1f s", $0) } ?? ""),
                  systemImage: "clock.arrow.circlepath")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
