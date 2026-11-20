import SwiftUI

/// On-device PDF summary the person can choose to share with their clinician.
@MainActor
enum ClinicianReport {
    static func make(model: AppModel) -> URL? {
        let view = ReportPage(state: model.state, plan: model.todaysPlan).frame(width: 612, height: 792)
        let renderer = ImageRenderer(content: view)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Motial-Ankle-Report.pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

private struct ReportPage: View {
    let state: StoredState
    let plan: [ClinicalEngine.PlanItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Motial · Ankle Rehabilitation Summary").font(.system(size: 18, weight: .bold))
                Spacer()
                Text(Date(), style: .date).font(.system(size: 10))
            }
            Divider()
            if let p = state.profile {
                row("Injured side", p.side.title)
                row("Days since injury (approx.)", "\(p.daysSinceInjury)")
                row("History", p.history.title + (p.givingWay ? " · reports giving way" : ""))
                row("Goal", p.goal.title)
                row("Age group", p.ageGroup.title)
                row("Hop clearance", p.hopClearance ? "Yes (reported)" : "No")
            }
            row("Current stage", "\(state.stage.rawValue). \(state.stage.title)")
            row("Sessions completed", "\(state.sessions.count)  (stopped early: \(state.sessions.filter(\.stoppedEarly).count))")
            if let first = state.checkIns.first, let last = state.checkIns.last {
                row("Rest pain (first → latest)", "\(first.painRest)/10 → \(last.painRest)/10")
            }
            let steady = state.sessions.flatMap(\.results).compactMap(\.steadiness)
            if let s0 = steady.first, let s1 = steady.last {
                row("Steadiness score (first → latest)", "\(Int(s0)) → \(Int(s1))  (experimental)")
            }
            let holds = state.sessions.flatMap(\.results).map(\.bestHold)
            row("Best single-leg hold", "\(Int(holds.max() ?? 0)) s")
            Divider()
            Text("Current programme").font(.system(size: 13, weight: .semibold))
            ForEach(plan) { i in
                Text("• \(i.exercise.title): \(i.dosage.text) (level \(i.level))").font(.system(size: 10))
            }
            let painful = state.adaptations.filter { $0.value.painFlags > 0 }.map { ExerciseLibrary.byID($0.key)?.title ?? $0.key }
            if !painful.isEmpty {
                Text("Exercises that provoked pain ≥ 4/10: \(painful.joined(separator: ", "))").font(.system(size: 10)).foregroundStyle(.red)
            }
            let stops = state.sessions.compactMap(\.stopReason)
            if !stops.isEmpty {
                Text("Stop events: \(stops.joined(separator: "; "))").font(.system(size: 10)).foregroundStyle(.red)
            }
            Spacer()
            Text("Programme logic follows the JOSPT 2021 Lateral Ankle Sprain CPG (Martin et al.), the BJSM 2018 ankle sprain guideline (Vuurberg et al.) and Hupperets et al., BMJ 2009. Steadiness is derived from headset head-sway and is not a validated clinical measure. Patient-reported data only.")
                .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color.white)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 10, weight: .semibold)).frame(width: 200, alignment: .leading)
            Text(v).font(.system(size: 10))
        }
    }
}
