import SwiftUI
import RealityKit

struct SessionImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var subscription: EventSubscription?

    var body: some View {
        if let session = model.activeSession {
            RealityView { content, attachments in
                content.add(session.world)
                if let hud = attachments.entity(for: "hud") {
                    hud.position = [0.62, 1.25, -1.3]
                    session.world.addChild(hud); session.hud = hud
                }
                if let orb = attachments.entity(for: "stop") {
                    orb.position = [-0.34, 1.2, -0.7]
                    session.world.addChild(orb); session.stopOrb = orb
                }
                subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    session.tick(dt: Float(event.deltaTime))
                }
                // Show the space (panel, STOP) straight away; the coach and tracking load in the background,
                // so a slow first load never leaves an empty room.
                Task { @MainActor in await session.setUp() }
            } attachments: {
                Attachment(id: "hud") { SessionHUD(session: session).environment(model) }
                Attachment(id: "stop") { StopOrbView(session: session) }
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                session.handleTap(value.entity)
            })
            .gesture(DragGesture().targetedToEntity(session.coach.root).onChanged { value in
                let p = value.convert(value.location3D, from: .local, to: .scene)
                session.moveCoach(to: SIMD3<Float>(Float(p.x), 0, Float(p.z)))
            })
            .onAppear { model.sessionRoomView = session.roomView }
            .onDisappear {
                subscription?.cancel()
                session.tearDown()
                model.immersiveOpen = false
                if !model.mainWindowOpen { openWindow(id: "main") }   // bring the main window back (hidden during sessions)
            }
        }
    }
}

/// Always-reachable emergency stop that follows the person gently.
struct StopOrbView: View {
    let session: SessionController
    var body: some View {
        Button(role: .destructive) {
            session.emergencyStop(.user)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "hand.raised.fill").font(.system(size: 26, weight: .bold))
                Text("STOP").font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(Circle().fill(Color.red.gradient))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .hoverEffect(.lift)
        .accessibilityLabel("Emergency stop")
        .accessibilityHint("Stops the exercise immediately")
    }
}

struct SessionHUD: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var session: SessionController
    @State private var checks = [false, false, false]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if session.phase != .safety && session.phase != .scan { timeline }
            if RehabTogether.shared.isActive {
                Label("SharePlay: \(max(0, RehabTogether.shared.participants - 1)) watching" + (RehabTogether.shared.lastCheer.map { " · “\($0)”" } ?? ""),
                      systemImage: "shareplay").font(.caption).foregroundStyle(.green)
            }
            Divider()
            content
        }
        .padding(28)
        .frame(width: session.phase == .active && session.exercise?.kind.isPedalGame == true ? 520 : 600)
        .glassBackgroundEffect()
    }

    private var header: some View {
        HStack {
            Label(session.stage.title, systemImage: session.stage.symbol)
                .font(.headline).foregroundStyle(session.stage.tint)
            Spacer()
            if session.phase != .safety { Text(session.progressText).font(.subheadline).foregroundStyle(.secondary) }
            Button {
                session.roomView.toggle()
                model.sessionRoomView = session.roomView
            } label: {
                Label(session.roomView ? "Show scenery" : "Show my room", systemImage: session.roomView ? "mountain.2.fill" : "house.fill")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Hide the virtual scenery so the coach trains with you in your own room")
            Button { session.bringCoachInFront() } label: {
                Image(systemName: "figure.stand.line.dotted.figure.stand")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help("Bring the coach back in front of you")
            .accessibilityLabel("Bring coach in front of me")
            Button {
                session.butterflyOn.toggle()
                var st = model.settings; st.butterfly = session.butterflyOn; model.settings = st
            } label: {
                Image(systemName: session.butterflyOn ? "sparkles" : "sparkles.slash")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help(session.butterflyOn ? "Hide Lumi, the butterfly guide" : "Show Lumi, the butterfly guide")
            .accessibilityLabel(session.butterflyOn ? "Hide butterfly guide" : "Show butterfly guide")
        }
    }

    /// Fitness+-style timeline: one segment per exercise; games are marked.
    private var timeline: some View {
        HStack(spacing: 4) {
            ForEach(Array(session.items.enumerated()), id: \.offset) { i, it in
                let done = i < session.index || session.phase == .summary
                let current = i == session.index && session.phase != .summary
                Capsule()
                    .fill(done ? Theme.accent : (current ? Theme.accent.opacity(0.6) : Color.white.opacity(0.15)))
                    .frame(height: current ? 8 : 6)
                    .overlay(alignment: .center) {
                        if case .game = it.exercise.kind { Circle().fill(.yellow).frame(width: 4, height: 4) }
                    }
                    .accessibilityLabel("\(it.exercise.title)\(done ? ", done" : current ? ", now" : "")")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .safety: safety
        case .scan: scan
        case .intro:
            if session.exercise?.kind.isPedalGame == true { PedalBriefing(session: session).environment(model) } else { intro }
        case .countdown(let n):
            Text("\(n)").font(.system(size: 120, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
                .contentTransition(.numericText()).accessibilityLabel("Starting in \(n)")
        case .active:
            if session.exercise?.kind.isPedalGame == true { PedalGameHUD(session: session) } else { active }
        case .rest: rest
        case .painCheck: painCheck
        case .summary: summary
        case .stopped(let reason): stopped(reason)
        }
    }

    // MARK: Safety
    // Calm, low-effort check: three tappable rows, one pain question, one button. Scenery choices are tucked away.
    @State private var showScenery = false
    private var safety: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to begin?").font(.motialTitle)
                Text(session.safetyConfirmed ? (needsScan ? "Rate your ankle, then a quick look around your space." : "Rate your ankle to start.") : "Tap each one when it's true.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            if !session.safetyConfirmed {
                VStack(spacing: 10) {
                    SafetyRow(symbol: "square.dashed", title: "Clear floor", detail: "About 2 × 2 m around you", on: $checks[0])
                    SafetyRow(symbol: "chair.fill", title: "Support within reach", detail: "A chair, wall or bench", on: $checks[1])
                    SafetyRow(symbol: "shoe.fill", title: "Non-slip footing", detail: "Bare feet or trainers", on: $checks[2])
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("How does your ankle feel? \(session.painBefore)/10").font(.title3.weight(.semibold))
                PainScale(value: $session.painBefore)
                if session.painBefore >= 6 {
                    Label("Let's keep it gentle today: seated exercises only, or rest and elevate.", systemImage: "heart.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            Button {
                session.confirmSafety()
            } label: {
                Label(needsScan ? "Scan my space" : "Continue", systemImage: needsScan ? "viewfinder" : "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.motialPrimary)
            .disabled(!(session.safetyConfirmed || checks.allSatisfy { $0 }) || session.painBefore >= 8)
            if !session.roomView {
                DisclosureGroup(isExpanded: $showScenery) {
                    EnvironmentPicker(session: session).padding(.top, 8)
                } label: {
                    Label("Scenery: \(session.environment.title)", systemImage: "mountain.2").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Standing work in the immersive scene walks the person through a room scan first.
    private var needsScan: Bool { !session.items.allSatisfy { $0.exercise.seated } }

    // MARK: Scan & calibrate
    private var scan: some View {
        let sc = session.scanner
        return VStack(alignment: .leading, spacing: 14) {
            Text("Scan & calibrate").font(.title2.bold())
            HStack(spacing: 22) {
                MetricRing(progress: sc.coverage, tint: sc.state == .done ? (sc.isSafe ? .green : .orange) : Theme.accent,
                           lineWidth: 10, label: "\(Int(sc.coverage * 100))%", caption: "looked around")
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Stand tall in the middle of your space", systemImage: "figure.stand")
                    Label("Slowly turn your head all the way around", systemImage: "arrow.triangle.2.circlepath")
                    Label("Glance down at the floor as you go", systemImage: "arrow.down.circle")
                }.font(.callout)
            }
            if sc.supported {
                Label(sc.floorFound ? "Floor found" : "Looking for the floor…", systemImage: sc.floorFound ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(sc.floorFound ? .green : .secondary)
            } else {
                Label("Room scanning isn't available here, so check around you by eye as you look.", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if sc.state == .done {
                Label(sc.summary, systemImage: sc.isSafe ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(sc.isSafe ? .green : .orange).font(.callout)
            }
            HStack {
                Button { session.rescan() } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                Spacer()
                if sc.state == .scanning && sc.coverage > 0.5 {
                    Button("Finish scan") { sc.finish() }
                }
                Button { session.finishScan() } label: {
                    Label(sc.isSafe || !sc.supported ? "Start" : "I've cleared it, start", systemImage: "play.fill").padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
                // Without room scanning (Simulator, or permission off) the person has already confirmed the space in
                // the activation sheet, so they can start straight away instead of waiting on a look-around.
                .disabled((sc.state != .done && sc.supported) || (sc.nearest.map { $0.distance < 0.5 } ?? false))
            }
            Text("Tip: tap “Show my room” to train in your own space with the coach. Pinch and drag the coach to move them somewhere clear.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Intro
    @State private var showWhy = false
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ex = session.exercise, let d = session.dosage {
                HStack(spacing: 18) {
                    Image(systemName: ex.symbol).font(.largeTitle).foregroundStyle(Theme.accent)
                        .frame(width: 80, height: 80).background(Theme.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading) {
                        Text(ex.title).font(.largeTitle.bold())
                        Text(d.text + (ex.singleLeg ? " · \(model.profile?.side.short ?? "") leg" : "")).font(.title3).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, s in
                    Label(s, systemImage: "\(i + 1).circle.fill").font(.body)
                }
                // secondary information, one tap away
                DisclosureGroup(isExpanded: $showWhy) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ex.purpose).font(.callout).foregroundStyle(.secondary)
                        MusclesView(exercise: ex, compact: true)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Why it helps and what's working", systemImage: "info.circle").font(.callout.weight(.semibold))
                }
                if !ex.cautions.isEmpty {
                    Label(ex.cautions.joined(separator: " "), systemImage: "shield.lefthalf.filled").font(.callout).foregroundStyle(.orange)
                }
                if case .game(.rhythmSteps) = ex.kind { SongPicker(session: session) }
                if case .game(.ballCatch) = ex.kind, !session.handTracking {
                    Label("Hand tracking is off: look at a ball and pinch to catch it.", systemImage: "hand.point.up.left").font(.callout)
                }
                HStack {
                    Toggle(isOn: $session.xray) { Label("See the ankle", systemImage: "eye") }.toggleStyle(.button)
                    Toggle(isOn: $session.mirror) { Label("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.toggleStyle(.button)
                    Button { session.toggleCoachView() } label: { Label("Side view", systemImage: "rotate.3d") }
                }
                HStack {
                    Button { session.skipExercise() } label: { Text("Skip") }
                    Spacer()
                    if case .game = ex.kind {
                        Button { session.startSet() } label: { Label("Activate Experience", systemImage: "visionpro") }
                            .buttonStyle(.motialPrimary)
                    } else {
                        Button { session.startSet() } label: { Label("Start", systemImage: "play.fill") }
                            .buttonStyle(.motialPrimary)
                    }
                }
            }
        }
    }

    // MARK: Active
    private var active: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ex = session.exercise, let d = session.dosage {
                HStack {
                    Text(ex.title).font(.title.bold())
                    Spacer()
                    Text("Set \(session.setNumber)/\(d.sets)").font(.title3.monospacedDigit())
                }
                HStack(spacing: 28) {
                    if let g = session.gameStatus, ex.kind != .hold, !(ex.kind == .game(.balanceBloom)) {
                        Text(g).font(.system(size: 44, weight: .bold, design: .rounded)).frame(maxWidth: .infinity)
                    } else if let hold = d.holdSeconds {
                        MetricRing(progress: 1 - session.remaining / Double(max(1, hold)), tint: Theme.accent,
                                   label: "\(Int(ceil(session.remaining)))", caption: "seconds")
                            .frame(width: 190, height: 190)
                    } else {
                        MetricRing(progress: Double(session.reps) / Double(max(1, d.reps ?? 1)), tint: .green,
                                   label: "\(session.reps)", caption: "of \(d.reps ?? 0) reps")
                            .frame(width: 190, height: 190)
                    }
                }
                .frame(maxWidth: .infinity)
                if ex.measure == .sway {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steadiness").font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: session.liveSteadiness).tint(session.liveSteadiness > 0.6 ? .green : .orange)
                    }
                }
                if !session.cue.isEmpty { Text(session.cue).font(.title3) }
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.functional").foregroundStyle(.orange)
                    Text("Working: " + ex.muscles.prefix(3).map(\.name).joined(separator: " · ")).font(.callout)
                }
                if let goal = ex.unlocks.first {
                    Label("Builds toward: \(goal)", systemImage: "flag.checkered").font(.caption).foregroundStyle(.secondary)
                }
                if let f = session.feedback { Text(f).font(.title3.bold()).foregroundStyle(.yellow) }
                HStack {
                    Button { session.togglePause() } label: {
                        Label(session.paused ? "Resume" : "Pause", systemImage: session.paused ? "play.fill" : "pause.fill")
                    }
                    Button { session.completeSetManually() } label: { Label("Set done", systemImage: "checkmark") }
                    Spacer()
                    Button { session.skipExercise() } label: { Text("Skip") }
                }
            }
        }
    }

    private var rest: some View {
        VStack(spacing: 10) {
            Text("Rest").font(.largeTitle.bold())
            Text("\(Int(ceil(session.remaining))) s").font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
            if let f = session.feedback { Text(f).font(.title3) }
            if let next = session.nextExercise, session.setNumber >= (session.dosage?.sets ?? 1) {
                HStack(spacing: 10) {
                    Image(systemName: next.symbol).foregroundStyle(Theme.accent).frame(width: 36, height: 36).background(Theme.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading) {
                        Text("Up next").font(.caption).foregroundStyle(.secondary)
                        Text(next.title).font(.headline)
                    }
                }
            }
            Button("Skip rest") { session.skipRest() }
        }.frame(maxWidth: .infinity)
    }

    // MARK: Pain check
    private var painCheck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did your ankle feel during that?").font(.title2.bold())
            Text("0 = no pain · 3 = fine · 5 = too much · 10 = worst").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(0...10, id: \.self) { p in
                    Button { session.submitPain(p) } label: {
                        Text("\(p)").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .tint(painColor(p))
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Pain \(p) out of 10")
                }
            }
        }
    }

    // MARK: Summary
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session complete").font(.largeTitle.bold())
            Text(ClinicalEngine.encouragement(stage: session.stage, profile: session.profile)).font(.title3)
            HStack(spacing: 24) {
                StatTile(title: "Exercises", value: "\(session.results.filter { !$0.skipped }.count)")
                // games (Dawn Drive, Lantern Glide) count orbs and gates, not reps: hide a misleading "0 reps"
                if session.totalReps > 0 { StatTile(title: "Reps", value: "\(session.totalReps)") }
                if let s = session.averageSteadiness { StatTile(title: "Steadiness", value: "\(Int(s))") }
                StatTile(title: "Minutes", value: "\(Int(Date().timeIntervalSince(session.started) / 60))")
            }
            trainedToday
            Text("Ankle pain now: \(session.painAfter)/10").font(.headline)
            PainScale(value: $session.painAfter)
            Text("Tip: some soreness that settles by tomorrow is OK. If it's worse tomorrow morning, the plan will ease off automatically.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                Task { await finish() }
            } label: { Label("Save & finish", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    /// What today's session trained, and what it builds toward.
    private var newBadges: [Badge] {
        var after = model.state
        after.sessions.append(session.record())
        return Badge.allCases.filter { Badge.earned(after).subtracting(Badge.earned(model.state)).contains($0) }
    }

    private var trainedToday: some View {
        let done = session.results.filter { !$0.skipped }.compactMap { r in ExerciseLibrary.byID(r.exerciseID) }
        let badges = newBadges
        let muscles = Array(Set(done.flatMap(\.muscles).map(\.name))).sorted()
        let goals = Array(Set(done.compactMap(\.unlocks.first))).sorted().prefix(4)
        return VStack(alignment: .leading, spacing: 8) {
            if !badges.isEmpty {
                Label("New badge\(badges.count > 1 ? "s" : "")!", systemImage: "rosette").font(.headline).foregroundStyle(.yellow)
                HStack(spacing: 12) {
                    ForEach(badges) { b in
                        VStack(spacing: 4) {
                            Image(systemName: b.symbol).font(.title2).foregroundStyle(.black)
                                .frame(width: 56, height: 56).background(Color.yellow.gradient, in: Circle())
                            Text(b.title).font(.caption.bold()).multilineTextAlignment(.center)
                        }.frame(width: 96)
                    }
                }
            }
            if !muscles.isEmpty {
                Label("Today you trained", systemImage: "figure.strengthtraining.functional").font(.headline).foregroundStyle(.orange)
                FlowChips(items: muscles)
            }
            if !goals.isEmpty {
                Label("You're building toward", systemImage: "flag.checkered").font(.headline).foregroundStyle(Theme.accent)
                ForEach(Array(goals), id: \.self) { Label($0, systemImage: "checkmark.circle").font(.callout) }
            }
        }
    }

    private func stopped(_ reason: SessionController.StopReason) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Stopped", systemImage: "hand.raised.fill").font(.largeTitle.bold()).foregroundStyle(.red)
            Text(reason.rawValue).font(.title3)
            VStack(alignment: .leading, spacing: 8) {
                Label("Hold on to something steady or sit down.", systemImage: "chair.lounge")
                Label("Rest, elevate and ice if the ankle is sore.", systemImage: "snowflake")
                Label("Get medical help if you can't take 4 steps, the pain is severe, or you hit your head.", systemImage: "cross.case.fill")
                    .foregroundStyle(.orange)
                Label("Singapore emergency: 995 · Advice: NurseFirst 6262 6262 · Your GP or physiotherapist", systemImage: "phone.fill")
                    .font(.callout)
                if let link = ClinicianCall.url(model.settings.clinicianLink) {
                    Link(destination: link) {
                        Label("Video call \(model.settings.clinicianName ?? "your physio")", systemImage: "video.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }.font(.body)
            HStack {
                Button { session.resumeAfterStop() } label: { Text("I'm OK, continue") }
                Spacer()
                Button { Task { await finish() } } label: { Text("End session") }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func finish() async {
        let record = session.record()
        model.record(session: record)
        model.activeSession = nil
        await dismissImmersiveSpace()
    }

    private func painColor(_ p: Int) -> Color {
        switch ClinicalEngine.zone(p) { case .green: return .green; case .amber: return .orange; case .red: return .red }
    }
}

struct EnvironmentPicker: View {
    @Bindable var session: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Scene", selection: $session.environment) {
                ForEach(EnvironmentKind.pickerCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if !session.fullImmersion {
                Picker("Coverage", selection: $session.coverage) {
                    ForEach(EnvironmentCoverage.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            if session.fullImmersion {
                Text("Fully immersive 360° with a virtual floor at your real floor height. Turn the Digital Crown to see your room.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if session.coverage == .full360 {
                Text("Room view: 360° is used only for seated exercises; standing ones switch to 180° so you can see your floor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SongPicker: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: SessionController
    var body: some View {
        let options = SongChoice.bundledTracks + model.state.importedSongs.map { SongChoice.imported($0) }
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, s in
                Button("\(s.title) · \(Int(s.bpm)) BPM") { session.song = s }
            }
        } label: {
            Label("Song: \(session.song.title)", systemImage: "music.note.list")
        }
    }
}


/// One big, calm, tappable safety check (whole row toggles; a filled check when done).
struct SafetyRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var on: Bool
    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30)).foregroundStyle(on ? Motial.success : Color.white.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .fixedSize(horizontal: false, vertical: true)
            .background(on ? Motial.success.opacity(0.14) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityValue(on ? "Checked" : "Not checked")
    }
}
