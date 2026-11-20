import SwiftUI
import RealityKit

struct SportLabImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var subscription: EventSubscription?

    var body: some View {
        if let lab = model.sportLab {
            RealityView { content, attachments in
                content.add(lab.world)
                if let hud = attachments.entity(for: "hud") {
                    hud.position = [0.62, 1.25, -1.25]
                    lab.world.addChild(hud); lab.hud = hud
                }
                if let orb = attachments.entity(for: "stop") {
                    orb.position = [-0.36, 1.15, -0.7]
                    lab.world.addChild(orb); lab.stopOrb = orb
                }
                subscription = content.subscribe(to: SceneEvents.Update.self) { e in lab.tick(dt: Float(e.deltaTime)) }
                await lab.setUp()
            } attachments: {
                Attachment(id: "hud") { SportLabHUD(lab: lab).environment(model) }
                Attachment(id: "stop") {
                    Button(role: .destructive) { lab.stop() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "hand.raised.fill").font(.system(size: 26, weight: .bold))
                            Text("STOP").font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.white).frame(width: 96, height: 96)
                        .background(Circle().fill(Color.red.gradient))
                    }
                    .buttonStyle(.plain).buttonBorderShape(.circle).hoverEffect(.lift)
                    .accessibilityLabel("Emergency stop")
                }
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { v in lab.handleTap(v.entity) })
            .onAppear { model.sportRoomView = !lab.onCourt }
            .onDisappear {
                subscription?.cancel()
                lab.record(into: model)
                lab.tearDown()
                model.immersiveOpen = false
                model.sportLab = nil
                if !model.mainWindowOpen { openWindow(id: "main") }
            }
        }
    }
}

/// Glass panel beside the person: drill picker, technique, reps, pain check and controls.
struct SportLabHUD: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Bindable var lab: SportLabController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Sport Lab · \(lab.drill.sport.title)", systemImage: lab.drill.sport.symbol)
                    .font(.headline).foregroundStyle(RehabStage.returnToActivity.tint)
                Spacer()
                Button {
                    lab.setOnCourt(!lab.onCourt); model.sportRoomView = !lab.onCourt
                } label: {
                    Label(lab.onCourt ? "Show my room" : "Show the court", systemImage: lab.onCourt ? "house.fill" : "sportscourt.fill")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lab.drills) { d in
                        let on = d.id == lab.drill.id
                        // selected: Pulse with ink text; others: plain glass (a white tint hid the white label)
                        Button { lab.choose(d) } label: {
                            Label(d.title, systemImage: d.symbol)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(on ? Motial.ink : .white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(on ? Motial.pulse : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .contentShape(.hoverEffect, Capsule())
                        .hoverEffect(.highlight)
                        .disabled(!(lab.phase == .watch || lab.phase == .done))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Divider()
            content
        }
        .padding(26).frame(width: 600).glassBackgroundEffect()
    }

    @ViewBuilder private var content: some View {
        switch lab.phase {
        case .watch: watch
        case .countdown(let n):
            Text("\(n)").font(.system(size: 110, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
        case .active:
            VStack(alignment: .leading, spacing: 10) {
                Text("Set \(lab.setNumber) of \(lab.drill.dosage.sets)").font(.headline).foregroundStyle(.secondary)
                Text("\(lab.reps) / \(lab.drill.dosage.reps ?? 5)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Copy the coach. Step on the glowing targets as they light up. Lumi flies to the next one.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("End set") { lab.finishSet() }.buttonStyle(.bordered)
            }
        case .rest:
            VStack(alignment: .leading, spacing: 8) {
                Label("Rest · breathe with Lumi", systemImage: "wind").font(.title3.bold())
                Text("\(max(0, lab.restLeft)) s").font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                Button("I'm ready") { lab.startPractice() }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        case .painCheck:
            VStack(alignment: .leading, spacing: 12) {
                Text("Ankle pain right now: \(lab.painDuring)/10").font(.title3.bold())
                PainScale(value: $lab.painDuring)
                Text("0–3 keep going · 4–5 we ease off · 6+ we stop").font(.caption).foregroundStyle(.secondary)
                Button("Continue") { lab.submitPain(lab.painDuring) }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        case .done:
            VStack(alignment: .leading, spacing: 10) {
                Label("Drill complete", systemImage: "checkmark.seal.fill").font(.title2.bold()).foregroundStyle(.green)
                Text("Choose another drill above, or finish. Keep balance training 3× a week, and wear a brace or tape for your first games back.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Finish") { Task { await dismissImmersiveSpace() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        case .stopped(let why):
            VStack(alignment: .leading, spacing: 10) {
                Label("Stopped", systemImage: "hand.raised.fill").font(.title2.bold()).foregroundStyle(.red)
                Text(why).font(.callout)
                Label("Singapore emergency: 995 · Advice: NurseFirst 6262 6262 · Your physio or GP", systemImage: "phone.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Close Sport Lab") { Task { await dismissImmersiveSpace() } }.buttonStyle(.bordered)
            }
        }
    }

    private var watch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lab.drill.title).font(.title2.bold())
            Text("\(lab.drill.dosage.text) · Watch the coach, then copy").font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(lab.drill.technique.enumerated()), id: \.offset) { i, t in
                Label(t, systemImage: "\(i + 1).circle.fill")
                    .foregroundStyle(i == lab.techniqueIndex ? Color.primary : .secondary)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Label("Avoid: " + lab.drill.commonMistakes.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            // the evidence behind the drill, in one line (full references in Sport Lab ▸ Clinical sources)
            Label("Based on: " + lab.drill.evidence.compactMap { EvidenceLibrary.byID($0)?.shortCite }.joined(separator: "; "),
                  systemImage: "text.book.closed")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { lab.startPractice() } label: { Label("My turn", systemImage: lab.drill.sport.symbol) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                if let url = model.clinicianVideoURL(for: lab.drill.videoKey) {
                    Button {
                        Task {
                            // only one immersive space can be open: close Sport Lab, then play the 360° video
                            await dismissImmersiveSpace()
                            model.videoToPlay = url
                            if case .opened = await openImmersiveSpace(id: "video") { model.immersiveOpen = true } else { model.videoToPlay = nil }
                        }
                    } label: { Label("Watch 360° demo", systemImage: "pano.fill") }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
