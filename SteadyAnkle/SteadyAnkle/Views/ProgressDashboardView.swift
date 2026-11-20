import SwiftUI
import Charts

struct ProgressDashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var reportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    GameRecordsCard()          // your drives: times, obstacles, orbs, bests
                    HStack(alignment: .top, spacing: 22) {
                        painChart
                        steadinessChart
                    }
                    HStack(alignment: .top, spacing: 22) {
                        adherenceChart
                        stageTimeline
                    }
                    badgeShelf
                    reportCard
                }
                .padding(32)
            }
            .navigationTitle("Progress")
        }
    }

    private var summary: some View {
        HStack(spacing: 22) {
            HeroCard(art: Theme.art(for: model.stage), symbol: model.stage.symbol,
                     eyebrow: "Day \(model.profile?.daysSinceInjury ?? 0) of recovery",
                     title: model.stage.title, subtitle: "Next: \(model.stage.exitCriteria)", height: 260)
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    MetricRing(progress: min(1, bestHold / 30), tint: Theme.accent, lineWidth: 10, label: "\(Int(bestHold))s", caption: "best one-leg")
                        .frame(width: 120, height: 120)
                    MetricRing(progress: min(1, Double(model.streakDays) / 7), tint: .orange, lineWidth: 10, label: "\(model.streakDays)", caption: "day streak")
                        .frame(width: 120, height: 120)
                }
                HStack(spacing: 16) {
                    MetricRing(progress: min(1, Double(model.state.sessions.count) / 24), tint: .green, lineWidth: 10, label: "\(model.state.sessions.count)", caption: "sessions")
                        .frame(width: 120, height: 120)
                    MetricRing(progress: 1 - Double(model.latestPain) / 10, tint: .pink, lineWidth: 10, label: "\(model.latestPain)", caption: "pain /10")
                        .frame(width: 120, height: 120)
                }
            }
            .padding(18)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    private var bestHold: Double {
        model.state.sessions.flatMap(\.results).map(\.bestHold).max() ?? 0
    }

    private var painChart: some View {
        Card {
            Text("Pain at rest").font(.title2.bold())
            if model.state.checkIns.count < 2 {
                Text("Your trend appears after a couple of check-ins.").foregroundStyle(.secondary)
            } else {
                Chart(model.state.checkIns) { c in
                    LineMark(x: .value("Date", c.date, unit: .day), y: .value("Pain", c.painRest))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", c.date, unit: .day), y: .value("Pain", c.painRest))
                }
                .chartYScale(domain: 0...10)
                .frame(height: 220)
            }
        }
    }

    private struct SteadyPoint: Identifiable { let id = UUID(); let date: Date; let value: Double }
    private var steadyPoints: [SteadyPoint] {
        model.state.sessions.compactMap { s in
            let v = s.results.compactMap(\.steadiness)
            return v.isEmpty ? nil : SteadyPoint(date: s.date, value: v.reduce(0, +) / Double(v.count))
        }
    }

    private var steadinessChart: some View {
        Card {
            Text("Balance steadiness").font(.title2.bold())
            Text("Experimental score from headset sway, used to track your training, not to diagnose.").font(.caption).foregroundStyle(.secondary)
            if steadyPoints.isEmpty {
                Text("Do a one-leg balance exercise to start this chart.").foregroundStyle(.secondary)
            } else {
                Chart(steadyPoints) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Steadiness", p.value)).opacity(0.25)
                    LineMark(x: .value("Date", p.date), y: .value("Steadiness", p.value))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 220)
            }
        }
    }

    private struct WeekCount: Identifiable { let id = UUID(); let week: Date; let count: Int }
    private var weekly: [WeekCount] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: model.state.sessions) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return groups.map { WeekCount(week: $0.key, count: $0.value.count) }.sorted { $0.week < $1.week }
    }

    private var adherenceChart: some View {
        Card {
            Text("Sessions per week").font(.title2.bold())
            Text("Target: \(model.stage >= .balance ? "3+" : "daily")").font(.caption).foregroundStyle(.secondary)
            if weekly.isEmpty {
                Text("No sessions yet.").foregroundStyle(.secondary)
            } else {
                Chart(weekly) { w in
                    BarMark(x: .value("Week", w.week, unit: .weekOfYear), y: .value("Sessions", w.count))
                }
                .frame(height: 200)
            }
        }
    }

    private var stageTimeline: some View {
        Card {
            Text("Your journey").font(.title2.bold())
            StageTrack(current: model.stage)
            ForEach(model.state.stageHistory.reversed()) { c in
                HStack {
                    StageBadge(stage: c.stage)
                    Spacer()
                    Text(c.date, style: .date).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var badgeShelf: some View {
        let earned = model.badges
        return Card {
            HStack {
                Text("Milestones").font(.title2.bold())
                Spacer()
                Text("\(earned.count) of \(Badge.allCases.count)").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                ForEach(Badge.allCases) { b in
                    let on = earned.contains(b)
                    VStack(spacing: 6) {
                        Image(systemName: b.symbol).font(.title2)
                            .foregroundStyle(on ? .black : .secondary)
                            .frame(width: 60, height: 60)
                            .background(on ? AnyShapeStyle(Color.yellow.gradient) : AnyShapeStyle(Color.white.opacity(0.08)), in: Circle())
                        Text(b.title).font(.caption.bold()).multilineTextAlignment(.center)
                        Text(b.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                    }
                    .padding(10).frame(maxWidth: .infinity)
                    .opacity(on ? 1 : 0.55)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(b.title), \(on ? "earned" : "not yet earned"). \(b.detail)")
                }
            }
        }
    }

    private var reportCard: some View {
        Card {
            Text("Share with your clinician").font(.title2.bold())
            Text("Creates a PDF summary on this device: stage, adherence, pain trend, balance scores and any sessions that were stopped. Nothing is uploaded.")
                .foregroundStyle(.secondary)
            HStack {
                Button { reportURL = ClinicianReport.make(model: model) } label: { Label("Create report", systemImage: "doc.richtext") }
                    .buttonStyle(.borderedProminent)
                if let u = reportURL {
                    ShareLink(item: u) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }
}
