import SwiftUI
import RealityKit
import simd

/// First-time onboarding in the person's own room (mixed immersion, nothing about the room changes):
/// the life-size coach introduces herself, Lumi flies in, STOP and the pain traffic light are shown for real,
/// and the coach demonstrates the first exercise of today's plan. About two minutes, skippable at any step.
@MainActor
@Observable
final class WelcomeTour {
    struct Step { let title: String; let body: String; let symbol: String }

    let profile: PatientProfile
    let firstExercise: Exercise?
    private(set) var index = 0
    let world = Entity()
    let coach = CoachRig()
    let butterfly = ButterflyGuide()
    let tracker = MotionTracker()
    private let stageRoot = Entity()
    private var lights: [ModelEntity] = []
    var hud: Entity?
    var stopOrb: Entity?
    private var clock: Double = 0
    /// Step 0: a glowing orb to practise "look, then pinch" (the gesture every button needs).
    private let practiceOrb = Entity()
    private let sparkles = Sparkles()
    private(set) var pinched = false

    init(profile: PatientProfile, firstExercise: Exercise?, settings: AppSettings) {
        self.profile = profile
        self.firstExercise = firstExercise
        coach.coach = settings.coach
        coach.mirror = settings.mirrorCoach
        coach.injured = profile.side
    }

    var steps: [Step] {
        let name = profile.nickname.isEmpty ? "" : ", \(profile.nickname)"
        let coachName = coach.coach == .fitness ? "Maya" : "Alex"
        return [
            // First time in a headset: learn the one gesture everything else needs, before anything else happens.
            Step(title: "Look, then pinch.", body: "Look at the glowing orb in front of you. Then lightly tap your thumb and index finger together. That's how you press anything here. Try it now.", symbol: "hand.tap.fill"),
            Step(title: "Hi\(name). I'm \(coachName).", body: "I'm your coach. I'll show you every exercise at life size, right here in your room. You can drag me to a clear spot.", symbol: "hand.wave.fill"),
            Step(title: "Meet Lumi", body: "Lumi shows you where to look and where to step, and breathes with you when you rest. Hold one hand out in front of you and keep it still. Lumi will come and land on it.", symbol: "sparkles"),
            Step(title: "STOP is always there", body: "Look at the red STOP button and pinch to pause at once. Then choose to carry on, or end the session. If it looks like you lost balance, everything stops by itself and shows who to call.", symbol: "hand.raised.fill"),
            Step(title: "Watch, then copy", body: firstExercise.map { "This is \($0.title), the first exercise in your plan. \($0.musclesSpoken)" } ?? "I'll demonstrate first, then you copy me.", symbol: "figure.cooldown"),
            Step(title: "Listen to your ankle", body: "After every exercise you rate your pain. Green 0–3: keep going. Amber 4–5: we make it easier. Red 6 or more: we stop.", symbol: "waveform.path.ecg"),
            Step(title: "Your room, your choice", body: "We recommend a calm 360° scene. You can choose your room instead before any session. In a scene, turn the Digital Crown, the dial on the top right of the headset, to bring your room back at any time.", symbol: "house.fill"),
        ]
    }

    func setUp() async {
        world.addChild(stageRoot)
        await coach.load()
        coach.root.position = [-0.55, 0, -2.1]
        coach.root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.7, 1.8, 0.5]).offsetBy(translation: [0, 0.9, 0])]))
        coach.root.components.set(InputTargetComponent())
        stageRoot.addChild(coach.root)
        coach.root.isEnabled = false           // hidden until the person has pinched once (step 1)
        coach.play(exercise: "idle")
        butterfly.visible = true
        butterfly.place(at: [0.4, 1.5, -1.3])
        world.addChild(butterfly.node)
        world.addChild(fallbackSpot)
        // From her very first approach Lumi looks for an outstretched hand and lands on it. The spoken line is kept
        // for the "Meet Lumi" step so earlier instructions are never interrupted.
        butterfly.seekHand = true
        butterfly.onLandedOnHand = { [weak self] in
            guard let self, !self.lumiLanded else { return }
            self.lumiLanded = true
            if self.index != 2 { self.butterfly.seekHand = false }
            SoundManager.shared.play("sfx_chime", volume: 0.6)
            if self.index == 2 {
                SoundManager.shared.say("Lumi landed on your hand. She'll guide you through every session.", interrupt: true)
            }
        }
        // traffic-light orbs for the pain step
        for (i, c) in [UIColor.systemGreen, .systemOrange, .systemRed].enumerated() {
            let o = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [EnvironmentBuilder.glow(c, opacity: 0.9)])
            o.position = [-0.02 + Float(i) * 0.17, 1.5, -1.4]   // between the coach and the panel
            o.isEnabled = false
            stageRoot.addChild(o); lights.append(o)
        }
        // practice orb: a calm teal glow at arm's length, a little below eye level; it highlights when looked at
        practiceOrb.addChild(ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [EnvironmentBuilder.glow(Palette.teal)]))
        practiceOrb.addChild(ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.25)]))
        practiceOrb.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.14)]))
        practiceOrb.components.set(InputTargetComponent())
        practiceOrb.components.set(HoverEffectComponent())
        practiceOrb.position = [0, 1.3, -0.9]
        practiceOrb.isEnabled = false
        stageRoot.addChild(practiceOrb)
        world.addChild(sparkles.root)
        stopOrb?.isEnabled = false
        // Start tracking without waiting on it (a permission prompt must never hold up the tour).
        Task { @MainActor in await self.tracker.start() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.place()
            self.enter(0)
        }
    }

    private func place() {
        tracker.update()
        let f = tracker.headForward
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        stageRoot.position = c; stageRoot.orientation = yawToward(f)
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        hud?.position = c + f * 1.25 + right * 0.6 + [0, max(1.15, tracker.head.y - 0.22), 0]
        hud?.orientation = yawToward(f)
        stopOrb?.position = c + f * 0.7 - right * 0.36 + [0, max(1.0, tracker.head.y - 0.42), 0]
        stopOrb?.orientation = yawToward(f)
    }

    func next() { if index < steps.count - 1 { enter(index + 1) } }
    func back() { if index > 0 { enter(index - 1) } }
    var isLast: Bool { index == steps.count - 1 }

    /// Fallback perch when hands can't be tracked (Simulator, or permission not given).
    private let fallbackSpot: ModelEntity = {
        let e = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.06),
                            materials: [EnvironmentBuilder.glow(Brand.lilac, opacity: 0.55)])
        e.isEnabled = false
        return e
    }()
    private var lumiHintAt: Double = 0
    private var lumiHinted = false
    private(set) var lumiLanded = false

    private func enter(_ i: Int) {
        index = i
        // seek a hand until Lumi has landed once, and again for the "Meet Lumi" step
        if i == 2 { lumiLanded = false }
        butterfly.seekHand = i == 2 || !lumiLanded
        lumiHintAt = clock + (tracker.handsAvailable ? 9 : 4); lumiHinted = false
        let s = steps[i]
        // titles are spoken as their own sentence (each has its own voice clip)
        let title = ".!?".contains(s.title.last ?? " ") ? s.title : s.title + "."
        SoundManager.shared.say("\(title) \(s.body)", interrupt: true)
        butterfly.visible = true
        practiceOrb.isEnabled = i == 0
        coach.root.isEnabled = i >= 1          // nothing else in the room until the person has pinched once
        stopOrb?.isEnabled = i >= 3
        lights.forEach { $0.isEnabled = i == 5 }
        switch i {
        case 0:
            pinched = false
            butterfly.mode = .hover(practiceOrb.position(relativeTo: nil) + [0.22, 0.14, 0])   // shows where to look
        case 2: butterfly.mode = .hover(tracker.head + tracker.headForward * 1.0 + [0, -0.1, 0])
        case 3: butterfly.mode = .perch((stopOrb?.position ?? [-0.36, 1.1, -0.7]) + [0, 0.12, 0])
        case 4:
            if let ex = firstExercise { coach.play(exercise: ex.clip, transition: 0.4) }
            butterfly.mode = .perch(coach.root.position(relativeTo: nil) + [0.2, 1.5, 0])
        case 5:
            coach.play(exercise: "idle", transition: 0.4)
            butterfly.mode = .hover((lights.first?.position(relativeTo: nil) ?? [0, 1.4, -1.4]) + [0.22, 0.18, 0])
        case 6: butterfly.mode = .breathe(tracker.head + tracker.headForward * 0.9 + [0, -0.2, 0])
        default:
            coach.play(exercise: "idle", transition: 0.4)
            butterfly.mode = .perch(coach.root.position(relativeTo: nil) + [0.25, 1.55, 0.1])   // on the coach's shoulder
        }
    }

    func tick(dt: Float) {
        clock += Double(dt)
        tracker.update()
        coach.tick(time: clock)
        // Either hand works: the one held higher and flatter is the one being offered to Lumi.
        let palm: (spot: SIMD3<Float>, flatness: Float)? = {
            switch (tracker.rightPalm, tracker.leftPalm) {
            case let (r?, l?): return (r.spot.y + r.flatness * 0.1) >= (l.spot.y + l.flatness * 0.1) ? r : l
            case let (r?, nil): return r
            case let (nil, l?): return l
            default: return nil
            }
        }()
        if index == 2 && !lumiLanded && !lumiHinted && clock > lumiHintAt {
            lumiHinted = true
            if tracker.handsAvailable {
                SoundManager.shared.say("Hold one hand out in front of you, about chest height, and keep it still.")
            } else {
                // Simulator, or hand tracking not allowed: Lumi rests on a soft glow in front of the person instead.
                fallbackSpot.position = tracker.head + tracker.headForward * 0.55 + [0, -0.35, 0]
                fallbackSpot.isEnabled = true
                butterfly.mode = .perch(fallbackSpot.position + [0, 0.03, 0])
                SoundManager.shared.say("Hand tracking isn't available here, so Lumi will rest in front of you.")
            }
        }
        if index != 2 { fallbackSpot.isEnabled = false }
        butterfly.update(dt: dt, time: clock, head: tracker.head, headForward: tracker.headForward,
                         hand: palm?.spot, handFlatness: palm?.flatness ?? 1)
        for (k, o) in lights.enumerated() where o.isEnabled {
            let s = Float(1 + 0.12 * sin(clock * 2 + Double(k)))
            o.scale = [s, s, s]
        }
        if practiceOrb.isEnabled && !pinched {
            let s = Float(1 + 0.1 * sin(clock * 2.4))       // a slow "breathing" glow invites a look
            practiceOrb.scale = [s, s, s]
        }
        sparkles.update(dt: dt)
    }

    /// Pinching the practice orb: a burst, a chime, a word of praise, then the tour moves on by itself.
    func handleTap(_ e: Entity) {
        var cur: Entity? = e
        while let c = cur {
            if c === practiceOrb, index == 0, !pinched {
                pinched = true
                sparkles.burst(at: practiceOrb.position(relativeTo: nil), color: Palette.teal, count: 26, speed: 0.7, size: 0.01)
                SoundManager.shared.play("sfx_chime", volume: 0.7)
                SoundManager.shared.say("Well done. That's a pinch. You'll use it for every button.", interrupt: true)
                practiceOrb.isEnabled = false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3.2))
                    if self.index == 0 { self.next() }
                }
                return
            }
            cur = c.parent
        }
    }

    /// Pinching the STOP button during the tour shows what it does, without stopping anything.
    func practiseStop() {
        guard index >= 3 else { return }
        SoundManager.shared.play("sfx_stop", volume: 0.5)
        SoundManager.shared.say("That's it. In a session, this pauses everything straight away.", interrupt: true)
    }

    func tearDown() { tracker.stop(); SoundManager.shared.stopVoice() }
}

struct WelcomeImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var subscription: EventSubscription?

    var body: some View {
        if let tour = model.welcome {
            RealityView { content, attachments in
                print("[Steady] welcome: RealityView make")
                content.add(tour.world)
                if let hud = attachments.entity(for: "hud") { hud.position = [0.6, 1.25, -1.25]; tour.world.addChild(hud); tour.hud = hud }
                if let orb = attachments.entity(for: "stop") { orb.position = [-0.36, 1.1, -0.7]; tour.world.addChild(orb); tour.stopOrb = orb }
                subscription = content.subscribe(to: SceneEvents.Update.self) { e in tour.tick(dt: Float(e.deltaTime)) }
                await tour.setUp()
            } attachments: {
                Attachment(id: "hud") { WelcomeHUD(tour: tour).environment(model) }
                Attachment(id: "stop") {
                    Button { tour.practiseStop() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "hand.raised.fill").font(.system(size: 26, weight: .bold))
                            Text("STOP").font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.white).frame(width: 96, height: 96)
                        .background(Circle().fill(Color.red.gradient))
                    }
                    .buttonStyle(.plain).buttonBorderShape(.circle).hoverEffect(.lift)
                    .accessibilityLabel("This is the STOP button")
                }
            }
            .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in tour.handleTap(value.entity) })
            .onDisappear {
                subscription?.cancel(); tour.tearDown()
                var st = model.settings; st.welcomeDone = true; model.settings = st
                model.immersiveOpen = false; model.welcome = nil
                if !model.mainWindowOpen { openWindow(id: "main") }
            }
        }
    }
}

struct WelcomeHUD: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var tour: WelcomeTour
    var body: some View {
        let s = tour.steps[tour.index]
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<tour.steps.count, id: \.self) { i in
                    Capsule().fill(i <= tour.index ? Theme.accent : Color.white.opacity(0.2)).frame(height: 6)
                }
            }
            Label(s.title, systemImage: s.symbol).font(.title2.bold())
            Text(s.body).font(.title3).fixedSize(horizontal: false, vertical: true)
            HStack {
                if tour.index > 0 { Button("Back") { tour.back() }.buttonStyle(.bordered) }
                Spacer()
                Button("Skip") { Task { await dismissImmersiveSpace() } }.buttonStyle(.borderless)
                Button(tour.isLast ? "Let's start" : "Next") {
                    if tour.isLast { Task { await dismissImmersiveSpace() } } else { tour.next() }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(28).frame(width: 560).glassBackgroundEffect()
    }
}

/// Today card shown until the first-time tour is done.
/// A plain card (text column + buttons on the glass, artwork as a clipped banner) so nothing can sit over the buttons.
struct WelcomeCard: View {
    @State private var errorText: String?
    @State private var opening = false
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(systemName: "hand.wave.fill").font(.system(size: 34)).foregroundStyle(Motial.navy)
                .frame(width: 84, height: 84).background(Motial.lilac, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("NEW TO VISION PRO?").font(.motialEyebrow).foregroundStyle(Motial.gold).tracking(1.4)
                Text("Meet your coach").font(.motialSection)
                Text("A two-minute welcome in your room: look and pinch, your coach, Lumi and the STOP button.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    ActivateExperienceButton(compact: true, disabled: opening || model.immersiveOpen) { await start() }
                    Button("Not now") {
                        var st = model.settings; st.welcomeDone = true; model.settings = st
                    }
                    .buttonStyle(.motialSecondary)
                }
                .padding(.top, 4)
                if let e = errorText { Text(e).font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
    }

    private func start() async {
        guard let p = model.profile else { errorText = "Finish setting up your profile first."; return }
        opening = true; defer { opening = false }
        if model.immersiveOpen { errorText = "Close the current session first."; return }
        model.welcome = WelcomeTour(profile: p, firstExercise: model.todaysPlan.first?.exercise, settings: model.settings)
        let result = await openImmersiveSpace(id: "welcome")
        switch result {
        case .opened:
            model.immersiveOpen = true
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
        default:
            model.welcome = nil
            errorText = "Couldn't open the welcome space. Close any other immersive app and try again."
        }
    }
}
