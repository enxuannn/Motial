import Foundation
import RealityKit
import UIKit
import simd

/// Runs one guided session in the immersive space: safety check → space scan & calibration → for each exercise: demo, countdown,
/// sets with live measurement, rest, pain check → summary. A STOP control is always available.
@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case safety
        case scan
        case intro
        case countdown(Int)
        case active
        case rest
        case painCheck
        case summary
        case stopped(StopReason)
    }
    enum StopReason: String, Equatable {
        case user = "You stopped the session."
        case possibleFall = "It looked like you lost balance."
        case pain = "Pain went too high."
        case dizzy = "You felt dizzy or unwell."
    }

    // Plan & person
    let items: [ClinicalEngine.PlanItem]
    let profile: PatientProfile
    let stage: RehabStage
    private(set) var adaptations: [String: ExerciseAdaptation]

    // Observable state for the HUD
    private(set) var phase: Phase = .safety
    private(set) var index = 0
    private(set) var setNumber = 1
    private(set) var remaining: Double = 0
    private(set) var reps = 0
    private(set) var cue = ""
    private(set) var feedback: String?
    private(set) var liveSteadiness: Double = 1
    private(set) var gameStatus: String?
    private(set) var gameStats: [GameStat] = []
    private(set) var pedalLevel: Float?
    private(set) var learnTip: String?
    private(set) var results: [ExerciseResult] = []
    var painBefore: Int
    var painAfter: Int = 0
    var environment: EnvironmentKind {
        didSet {
            rebuildEnvironment()
            butterfly.setPlace(environment)
            if oldValue != environment { SoundManager.shared.say("\(environment.title). \(environment.narration)", interrupt: true) }
        }
    }
    var coverage: EnvironmentCoverage { didSet { rebuildEnvironment() } }
    var xray = false { didSet { coach.setXray(xray) } }
    var mirror: Bool { didSet { coach.mirror = mirror; coach.refreshSide() } }
    var song: SongChoice = .bundled("music_step_up", bpm: 104)
    private(set) var paused = false
    private(set) var handTracking = false
    private(set) var coachSideView = false
    let started = Date()
    let coachModel: CoachModel

    // Runtime (not observed)
    let tracker = MotionTracker()
    let scanner = SpaceScanner()
    /// Room view: hide the scenery so the coach trains with the person in their own home (mixed immersion).
    /// The clear-space checks were already confirmed in the activation sheet (the HUD then only asks about pain).
    var safetyConfirmed = false
    /// Opened from a game card: skip the second "Activate Experience" in the intro.
    var directStart = false
    var roomView: Bool { didSet { if oldValue != roomView { rebuildEnvironment(); announceRoomView() } } }
    var fullImmersion: Bool { !roomView }
    let coach = CoachRig()
    let world = Entity()
    @ObservationIgnored var hud: Entity?
    @ObservationIgnored var stopOrb: Entity?
    @ObservationIgnored private var envEntity: Entity?
    @ObservationIgnored private var safeZone: Entity?
    @ObservationIgnored private var game: RehabGame?
    @ObservationIgnored private var sway = SwayMeter()
    @ObservationIgnored private var repCounter: HeadRepCounter?
    @ObservationIgnored private var hops = HopDetector()
    @ObservationIgnored private var clock: Double = 0
    @ObservationIgnored private var phaseTimer: Double = 0
    @ObservationIgnored private var cueTimer: Double = 0
    @ObservationIgnored private var cueIndex = 0
    @ObservationIgnored private var tempoTimer: Double = 0
    @ObservationIgnored private var bestHold: Double = 0
    @ObservationIgnored private var steadinessSamples: [Double] = []
    @ObservationIgnored private var placed = false
    @ObservationIgnored private var forward = SIMD3<Float>(0, 0, -1)
    @ObservationIgnored private var shareTimer: Double = 0
    @ObservationIgnored private var garden = Entity()
    @ObservationIgnored private var reactor: WorldReactor?
    /// Lumi, the companion butterfly that shows where to look and step.
    let butterfly = ButterflyGuide()
    var butterflyOn: Bool { didSet { butterfly.visible = butterflyOn } }
    @ObservationIgnored private var lastGameScore = 0
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var gameStart = Date()
    @ObservationIgnored private var hudHome: SIMD3<Float>?
    @ObservationIgnored private var hudHomeOrientation: simd_quatf?
    @ObservationIgnored private var spokeBreathing = false

    init(items: [ClinicalEngine.PlanItem], profile: PatientProfile, stage: RehabStage, settings: AppSettings,
         adaptations: [String: ExerciseAdaptation], painBefore: Int) {
        self.items = items
        self.profile = profile
        self.stage = stage
        self.adaptations = adaptations
        self.painBefore = painBefore
        self.environment = settings.defaultEnvironment
        self.coverage = settings.coverage
        self.mirror = settings.mirrorCoach
        self.coachModel = settings.coach
        self.butterflyOn = settings.butterfly ?? true
        self.reduceMotion = settings.reduceMotion
        // The background never changes on its own: the person's room unless they chose immersive scenery.
        self.roomView = settings.roomView ?? false
        if !(settings.roomView ?? false) { self.coverage = .full360 }
        // Stepping and hopping games need more room than standing balance work.
        let needsRoom = items.contains { ["stepping_stones", "river_hops", "rhythm_steps", "hop_forward", "side_hop"].contains($0.exercise.id) }
        scanner.requiredClearance = needsRoom ? 1.5 : 1.0
    }

    var item: ClinicalEngine.PlanItem? { items.indices.contains(index) ? items[index] : nil }
    var exercise: Exercise? { item?.exercise }
    var dosage: Dosage? { item?.dosage }
    var progressText: String { "Exercise \(min(index + 1, items.count)) of \(items.count)" }
    /// Full immersion (360°, with a virtual floor at the real floor height) is used after the space scan.
    /// In room view (mixed), standing exercises keep the real floor visible, so 360° falls back to 180°.
    var effectiveCoverage: EnvironmentCoverage {
        if fullImmersion { return .full360 }
        return (exercise?.seated ?? false) || phase == .summary ? coverage : (coverage == .full360 ? .arc180 : coverage)
    }
    var isStanding: Bool { !(exercise?.seated ?? true) }

    // MARK: Setup

    func setUp() async {
        world.name = "SessionWorld"
        coach.injured = profile.side
        coach.coach = coachModel
        coach.mirror = mirror
        await coach.load()
        // Default layout (refined by placeScene once head tracking runs): coach ahead-left, panel ahead-right,
        // so the coach, the panel and the STOP button never overlap.
        coach.root.position = [-0.6, 0, -2.1]
        // grab-and-move: the person can drag the coach to a free spot in their room
        coach.root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.7, 1.8, 0.5]).offsetBy(translation: [0, 0.9, 0])]))
        coach.root.components.set(InputTargetComponent())
        coach.root.components.set(HoverEffectComponent())
        world.addChild(coach.root)
        butterfly.setPlace(environment)
        butterfly.visible = butterflyOn
        butterfly.place(at: [0.3, 1.3, -1.0])
        world.addChild(butterfly.node)
        // On her first approach Lumi lands on an outstretched hand (either hand); after that she keeps her normal
        // guide behaviour and only visits a hand held out in front.
        butterfly.seekHand = true
        butterfly.onLandedOnHand = { [weak self] in
            guard let self else { return }
            if self.butterfly.seekHand { SoundManager.shared.play("sfx_chime", volume: 0.5) }
            self.butterfly.seekHand = false
        }
        coach.play(exercise: "idle")
        await tracker.start()
        handTracking = tracker.handsAvailable
        rebuildEnvironment()
        SoundManager.shared.startAmbience(environment.ambience)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            self.placeScene()
        }
        SoundManager.shared.say("Hi there. Welcome to \(environment.title). \(environment.narration)\(butterflyOn ? " This is Lumi, your butterfly guide. Lumi will show you where to look and where to step." : "")\(safetyConfirmed ? " Your space is checked. Rate your ankle to begin." : " Before we start, let's make sure your space is safe. Answer the quick checks, then we'll scan the room together.")")
    }

    /// The coach, the panel and the scenery are placed ONCE, in front of the person, and then stay anchored to that
    /// world position: they never follow, orbit or turn with the person's head (the room scan asks people to turn
    /// all the way around). Only a deliberate action moves the coach: dragging her, or "Bring coach in front".
    private func placeScene(force: Bool = false) {
        tracker.update()
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        safeZone?.removeFromParent()
        let z = EnvironmentBuilder.safeZone()
        z.position = c
        world.addChild(z); safeZone = z
        guard !placed || force else { return }
        let f = tracker.headForward
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        coach.root.position = c + f * 2.1 - right * 0.55
        coach.root.orientation = yawToward(f)
        hud?.position = c + f * 1.3 + right * 0.62 + [0, max(1.15, tracker.head.y - 0.22), 0]
        hud?.orientation = yawToward(f)
        if !placed {
            // the scenery is set up once, facing the way the person first looked
            forward = f
            envEntity?.orientation = yawToward(f)
        }
        placed = true
    }

    /// Deliberate repositioning: the coach (and the panel) come back to stand in front of the person.
    func bringCoachInFront() {
        placeScene(force: true)
        SoundManager.shared.play("sfx_tap")
    }

    private func announceRoomView() {
        SoundManager.shared.say(roomView ? "Here's your room. I'll train with you right here. Keep the floor around you clear."
                                         : "Back to \(environment.title).", interrupt: true)
    }

    /// Move the coach (e.g. away from furniture in room view), keeping them on the floor and facing the person.
    func moveCoach(to p: SIMD3<Float>) {
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        var target = SIMD3<Float>(p.x, 0, p.z)
        let d = simd_distance(SIMD2<Float>(target.x, target.z), SIMD2<Float>(c.x, c.z))
        if d < 1.2 { // keep at least 1.2 m away so the person never steps into the coach
            let dir = simd_normalize(SIMD3<Float>(target.x - c.x, 0, target.z - c.z) + [0, 0, 1e-4])
            target = c + dir * 1.2
        }
        coach.root.position = target
        let toPerson = simd_normalize(SIMD3<Float>(c.x - target.x, 0, c.z - target.z))
        coach.root.orientation = yawToward(-toPerson)
    }

    private func rebuildEnvironment() {
        envEntity?.removeFromParent()
        if roomView {
            removeIBL(coach.root)                     // the real room's light again
            let e = Entity(); e.name = "Environment"   // no scenery: the real room shows through
            world.addChild(e); envEntity = e
            SoundManager.shared.startAmbience(environment.ambience)
            return
        }
        let e = EnvironmentBuilder.make(environment, coverage: effectiveCoverage)
        e.orientation = yawToward(forward)
        world.addChild(e)
        envEntity = e
        // the coach takes the scene's light (dawn meadow, night lanterns…) so she belongs to the place
        Task { @MainActor [weak self, weak e] in
            for _ in 0..<50 {
                if let light = e?.findEntity(named: "SceneLight"), let c = self?.coach.root {
                    SportLabController.applyIBL(light, to: c); return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        SoundManager.shared.startAmbience(environment.ambience)
    }

    private func removeIBL(_ e: Entity) {
        e.components.remove(ImageBasedLightReceiverComponent.self)
        for c in e.children { removeIBL(c) }
    }

    // MARK: Flow controls (called from the HUD)

    func confirmSafety() {
        tracker.calibrate()
        placeScene()
        SoundManager.shared.play("sfx_tap")
        phase = .scan
        // Seated-only sessions don't need a walk-around room scan, and without head tracking (Simulator)
        // the look-around can't complete: go straight to the exercise.
        if items.allSatisfy({ $0.exercise.seated }) || !tracker.running {
            finishScan()
            return
        }
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        Task { await scanner.start(centre: c) }
        SoundManager.shared.say(butterflyOn
            ? "Now stand tall in the middle of your space. Follow Lumi with your eyes as it circles the room, turning slowly and looking at the floor as you go. I'm checking for anything you could trip over."
            : "Now stand tall in the middle of your space, and slowly turn your head all the way around, looking at the floor as you go. I'm checking for anything you could trip over.", interrupt: true)
    }

    /// Re-run the scan after the person has moved or cleared something.
    func rescan() {
        tracker.calibrate()
        placeScene()
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        Task { await scanner.start(centre: c) }
        SoundManager.shared.say("Scanning again. Slowly look all the way around.", interrupt: true)
    }

    /// After the scan: calibrate standing height again and start the first exercise.
    func finishScan() {
        tracker.calibrate()
        placeScene()
        scanner.stop()
        SoundManager.shared.play("sfx_success", volume: 0.6)
        SoundManager.shared.say(scanner.isSafe ? "Great, your space is ready. You can turn the Digital Crown at any time to see your room." : "Okay. Keep your support close and stay inside the blue ring.", interrupt: true)
        beginIntro()
    }

    private func beginIntro() {
        guard let ex = exercise else { finish(); return }
        phase = .intro
        setNumber = 1
        reps = 0
        feedback = nil
        bestHold = 0
        steadinessSamples = []
        rebuildEnvironment()
        coach.play(exercise: ex.clip)
        let d = dosage.map { $0.text } ?? ""
        cue = ex.steps.first ?? ""
        SoundManager.shared.say("\(ex.title). \(d). \(ex.steps.joined(separator: " ")) \(ex.musclesSpoken)", interrupt: true)
        // launched straight from a game card (Play tab): it was already activated once, so it starts by itself
        if directStart, case .game = ex.kind {
            directStart = false
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                if self?.phase == .intro { self?.startSet() }
            }
        }
    }

    func startSet() {
        guard exercise != nil else { return }
        if isStanding { tracker.calibrate() }
        phase = .countdown(3)
        phaseTimer = 0
        SoundManager.shared.play("sfx_tick")
    }

    private func beginActive() {
        guard let ex = exercise, let d = dosage else { return }
        phase = .active
        phaseTimer = 0; cueTimer = 0; cueIndex = 0; tempoTimer = 0
        reps = 0
        sway.reset()
        SoundManager.shared.play("sfx_go", volume: 0.8)
        coach.play(exercise: ex.clip)
        switch ex.measure {
        case .headReps:
            var r = HeadRepCounter(direction: ex.id == "sl_mini_squat" ? .down : .up)
            r.threshold = ex.id == "sl_mini_squat" ? 0.04 : 0.028
            repCounter = r
        case .hops:
            hops = HopDetector(); hops.baseline = tracker.standingHeight
        default: repCounter = nil
        }
        remaining = Double(d.holdSeconds ?? 0)
        if case .game(let kind) = ex.kind { startGame(kind, dosage: d) }
    }

    private func startGame(_ kind: GameKind, dosage d: Dosage) {
        var cfg = GameConfig()
        cfg.level = item?.level ?? 1
        cfg.injured = profile.side
        cfg.song = song
        cfg.environment = environment
        cfg.setNumber = setNumber
        cfg.fallRisk = profile.fallRisk
        switch kind {
        case .balanceBloom:
            game = BalanceBloomGame(config: cfg)
            remaining = Double(d.holdSeconds ?? 20)
        case .ballCatch:
            cfg.count = d.reps ?? 8
            game = CatchGame(config: cfg)
        case .riverStones:
            cfg.hops = exercise?.id == "river_hops"
            game = RiverStonesGame(config: cfg)
        case .rhythmSteps:
            cfg.rhythmMode = ClinicalEngine.rhythmMode(stage: stage, profile: profile, level: cfg.level)
            cfg.hops = cfg.rhythmMode == .hop
            cfg.count = [10, 14, 18][cfg.level - 1]          // rehab dose, not a workout
            game = RhythmStepGame(config: cfg)
        case .lanternGlide:
            cfg.count = [6, 8, 10][max(0, min(2, cfg.level - 1))]   // lanterns on the route (≈ 1–2 heel raises each)
            cfg.seated = exercise?.seated ?? false
            game = LanternGlideGame(config: cfg)
        case .dawnDrive:
            cfg.seated = exercise?.seated ?? false
            game = DawnDriveGame(config: cfg)
        case .cockpitDrive:
            cfg.seated = true
            cfg.reduceMotion = reduceMotion
            game = CockpitDriveGame(config: cfg)
        case .wordGarden:
            cfg.coachAnchor = coach.root.position(relativeTo: world)
            game = LetterGardenGame(config: cfg)
        }
        lastGameScore = 0
        gameStart = Date()
        if let g = game {
            world.addChild(g.root)
            g.start(tracker: tracker)
            if g.hidesCoach {
                coach.root.isEnabled = false
                // in the cockpit, float the panel up and to the right, clear of the car body
                if let h = hud {
                    hudHome = h.position; hudHomeOrientation = h.orientation
                    var f = tracker.headForward; f.y = 0
                    f = simd_length(f) > 0.01 ? simd_normalize(f) : [0, 0, -1]
                    let right = simd_normalize(simd_cross(f, [0, 1, 0]))
                    let c = SIMD3<Float>(tracker.centre.x, 0, tracker.centre.z)
                    h.position = c + f * 0.95 + right * 0.78 + [0, tracker.head.y + 0.12, 0]
                    h.orientation = yawToward(simd_normalize(SIMD3<Float>(c.x, 0, c.z) - SIMD3<Float>(h.position.x, 0, h.position.z)) * -1)
                }
            } else if kind == .wordGarden, let h = hud {
                // Word Garden: the letter board takes the centre, so the panel moves out to the right and lower
                hudHome = h.position; hudHomeOrientation = h.orientation
                var f = tracker.headForward; f.y = 0
                f = simd_length(f) > 0.01 ? simd_normalize(f) : [0, 0, -1]
                let right = simd_normalize(simd_cross(f, [0, 1, 0]))
                let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
                h.position = c + f * 1.0 + right * 0.95 + [0, max(0.8, tracker.head.y - 0.25), 0]
                h.orientation = yawToward(simd_normalize(SIMD3<Float>(h.position.x, 0, h.position.z) - c))
            }
        }
    }

    func togglePause() {
        paused.toggle()
        game?.setPaused(paused)
        if paused { SoundManager.shared.stopVoice(); coach.play(exercise: (exercise?.seated ?? false) ? "seated_idle" : "idle") }
        else if let ex = exercise { coach.play(exercise: ex.clip) }
    }

    func skipRest() { if phase == .rest { nextSetOrPainCheck(force: true) } }

    func completeSetManually() { if phase == .active { finishSet() } }

    func skipExercise() {
        guard let ex = exercise else { return }
        endGame()
        var r = ExerciseResult(exerciseID: ex.id)
        r.skipped = true
        r.setsTarget = dosage?.sets ?? 0
        results.append(r)
        advance()
    }

    func toggleCoachView() {
        coachSideView.toggle()
        coach.model?.orientation = coachSideView ? simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) : simd_quatf()
    }

    // MARK: Safety

    func emergencyStop(_ reason: StopReason) {
        if case .stopped = phase { return }
        endGame()
        SoundManager.shared.stopVoice()
        SoundManager.shared.stopMusic()
        SoundManager.shared.play("sfx_stop")
        coach.play(exercise: "idle", transition: 0.2)
        if let ex = exercise, phase == .active || phase == .rest || phase == .countdown(3) || phase == .countdown(2) || phase == .countdown(1) {
            var r = ExerciseResult(exerciseID: ex.id)
            r.setsDone = max(0, setNumber - 1); r.setsTarget = dosage?.sets ?? 0
            r.painDuring = reason == .pain ? 7 : nil
            results.append(r)
        }
        phase = .stopped(reason)
        switch reason {
        case .possibleFall: SoundManager.shared.say("Stopping. Take a moment. Hold on to something steady, or sit down.", interrupt: true)
        case .pain: SoundManager.shared.say("Stopping. Let's rest the ankle.", interrupt: true)
        case .dizzy: SoundManager.shared.say("Stopping. Sit down and take slow breaths.", interrupt: true)
        case .user: SoundManager.shared.say("Session paused safely.", interrupt: true)
        }
    }

    /// Resume after a stop if the person feels fine.
    func resumeAfterStop() {
        guard case .stopped(let reason) = phase else { return }
        SoundManager.shared.play("sfx_tap")
        if exercise == nil { finish(); return }
        // Never repeat the exercise that just hurt; move on to the next one instead.
        if reason == .pain { advance() } else { beginIntro() }
    }

    func endFromStop() { finish() }

    // MARK: Pain check

    func submitPain(_ pain: Int) {
        guard let ex = exercise else { return }
        if var last = results.last, last.exerciseID == ex.id, results.count > 0 {
            last.painDuring = pain
            results[results.count - 1] = last
        }
        switch ClinicalEngine.zone(pain) {
        case .green:
            SoundManager.shared.say(ClinicalEngine.encouragement(stage: stage, profile: profile, seed: index + pain))
            advance()
        case .amber:
            feedback = "Noted. We'll go easier on this one next time."
            SoundManager.shared.say("Thanks. We'll make it a little easier next time.")
            advance()
        case .red:
            emergencyStop(.pain)
        }
    }

    // MARK: Frame update

    func tick(dt: Float) {
        clock += Double(dt)
        SessionClock.now = clock
        shareTimer += Double(dt)
        if shareTimer > 1, RehabTogether.shared.isActive { shareTimer = 0; broadcastLive() }
        tracker.update()
        coach.tick(time: clock)
        reactor?.update(dt: dt)
        updateButterfly(dt: dt)
        followStopOrb()
        guard !paused else { return }
        phaseTimer += Double(dt)

        if isStanding, phase == .active, tracker.running, tracker.fallLike(hopping: exercise?.measure == .hops || exercise?.id == "river_hops" || exercise?.id == "rhythm_steps") {
            emergencyStop(.possibleFall); return
        }

        switch phase {
        case .scan:
            let wasScanning = scanner.state == .scanning
            scanner.update(headForward: tracker.headForward, head: tracker.head)
            if wasScanning && scanner.state == .done {
                SoundManager.shared.play("sfx_levelup", volume: 0.6)
                SoundManager.shared.say(scanner.summary, interrupt: true)
            }
        case .countdown(let n):
            if phaseTimer >= 1 {
                phaseTimer = 0
                if n > 1 { phase = .countdown(n - 1); SoundManager.shared.play("sfx_tick") } else { beginActive() }
            }
        case .active:
            runActive(dt: dt)
        case .rest:
            remaining = max(0, remaining - Double(dt))
            if remaining <= 0 { nextSetOrPainCheck(force: false) }
        default:
            break
        }
    }

    private func followStopOrb() {
        guard let orb = stopOrb, tracker.running else { return }
        let f = tracker.headForward
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        // lower-left of view, so it never covers the session panel on the right
        let target = tracker.head + f * 0.7 - right * 0.34 + [0, -0.38, 0]
        let p = orb.position
        orb.position = p + (target - p) * 0.06
        orb.orientation = simd_slerp(orb.orientation, yawToward(f), 0.06)
    }

    private func runActive(dt: Float) {
        guard let ex = exercise, let d = dosage else { return }
        // spoken cues every ~6 s
        cueTimer += Double(dt)
        if cueTimer > 6.5, !ex.cues.isEmpty {
            cueTimer = 0
            cue = ex.cues[cueIndex % ex.cues.count]
            cueIndex += 1
            SoundManager.shared.say(cue)
        }
        // measurement
        if ex.measure == .sway {
            sway.add(tracker.head)
            liveSteadiness = sway.liveSteadiness
        }
        if let g = game {
            g.update(dt: dt, time: clock, tracker: tracker)
            if g.score > lastGameScore { lastGameScore = g.score; butterfly.celebrate(color: reactorColor) }
            gameStatus = g.status
            gameStats = g.stats
            pedalLevel = g.pedalLevel
            learnTip = g.learnTip
            if let f = g.feedback { feedback = f }
            if case .game(.balanceBloom) = ex.kind {
                remaining = max(0, remaining - Double(dt))
                if remaining <= 0 { finishSet() }
            } else if g.finished || phaseTimer > (ex.kind == .game(.wordGarden) ? 300 : 150) {
                finishSet()
            }
            return
        }
        switch ex.kind {
        case .hold:
            remaining = max(0, remaining - Double(dt))
            if remaining <= 0 { finishSet() }
        case .reps:
            let target = d.reps ?? 10
            if ex.measure == .headReps, tracker.running, var rc = repCounter {
                rc.add(tracker.head.y); repCounter = rc
                if rc.count > reps { reps = rc.count; SoundManager.shared.play("sfx_beat", volume: 0.5); stepEffect(strength: 0.5) }
            } else if ex.measure == .hops, tracker.running {
                if let ev = hops.add(head: tracker.head, velocityY: tracker.headVelocity.y), case .landing = ev {
                    reps += 1; SoundManager.shared.play("sfx_stone", volume: 0.6); stepEffect(strength: 1)
                }
            } else {
                // guided tempo (seated / unmeasured exercises)
                tempoTimer += Double(dt)
                if tempoTimer >= tempo(ex) {
                    tempoTimer = 0; reps += 1
                    SoundManager.shared.play("sfx_beat", volume: 0.35)
                }
            }
            if reps >= target { finishSet() }
            if phaseTimer > Double(target) * 8 + 20 { finishSet() }    // never stuck
        case .game:
            break
        }
    }

    private func tempo(_ ex: Exercise) -> Double {
        switch ex.id {
        case "ankle_pumps": return 2.0
        case "ankle_alphabet": return 26
        case "seated_eversion": return 4.5
        case "knee_to_wall": return 4.5
        case "calf_raise", "sl_calf_raise": return 4.2
        case "sl_mini_squat": return 4.6
        default: return 4.0
        }
    }

    private func finishSet() {
        guard let ex = exercise, let d = dosage else { return }
        let hold = phaseTimer
        if ex.measure == .sway {
            bestHold = max(bestHold, ex.kind == .hold ? Double(d.holdSeconds ?? 0) : hold)
            steadinessSamples.append(game.map { g in (g as? BalanceBloomGame)?.steadiness ?? (g as? CatchGame)?.steadiness ?? sway.score } ?? sway.score)
        }
        var r = currentResult(for: ex)
        r.setsDone = setNumber
        r.setsTarget = d.sets
        r.reps += reps
        r.bestHold = bestHold
        if !steadinessSamples.isEmpty { r.steadiness = steadinessSamples.reduce(0, +) / Double(steadinessSamples.count) }
        if let g = game { r.gameScore = (r.gameScore ?? 0) + g.score }
        storeResult(r)
        endGame()
        SoundManager.shared.play("sfx_success", volume: 0.7)
        if setNumber < d.sets {
            phase = .rest
            remaining = Double(d.restSeconds)
            feedback = butterflyOn ? "Set \(setNumber) done. Breathe with Lumi: in as the wings open, out as they close." : "Set \(setNumber) done. Rest and shake it out."
            if butterflyOn && !spokeBreathing {
                spokeBreathing = true
                SoundManager.shared.say("Set \(setNumber) done. Great work. While you rest, breathe with Lumi. Breathe in as the wings open, and out as they close.")
            } else {
                SoundManager.shared.say("Set \(setNumber) done. Great work. Rest.")
            }
            coach.play(exercise: ex.seated ? "seated_idle" : "idle")
        } else {
            phase = .painCheck
            feedback = nil
            coach.play(exercise: ex.seated ? "seated_idle" : "idle")
            SoundManager.shared.say("Exercise complete. How does the ankle feel?")
        }
    }

    private func nextSetOrPainCheck(force: Bool) {
        guard let d = dosage else { return }
        if setNumber < d.sets { setNumber += 1; startSet() } else { phase = .painCheck }
    }

    private func currentResult(for ex: Exercise) -> ExerciseResult {
        if let last = results.last, last.exerciseID == ex.id, !last.skipped { return last }
        return ExerciseResult(exerciseID: ex.id)
    }
    private func storeResult(_ r: ExerciseResult) {
        if let last = results.last, last.exerciseID == r.exerciseID, !last.skipped {
            results[results.count - 1] = r
        } else { results.append(r) }
    }

    private func endGame() {
        coach.root.isEnabled = true
        if let p = hudHome { hud?.position = p; if let o = hudHomeOrientation { hud?.orientation = o }; hudHome = nil }
        // keep a record of pedal-game runs (Progress › Your drives)
        if let g = game, let ex = exercise, let s = g.summary {
            let secs = Date().timeIntervalSince(gameStart)
            if secs > 8 {
                GameLog.shared.add(GameRecord(date: Date(), exerciseID: ex.id, title: ex.title, seconds: secs, orbs: s.orbs,
                                              obstaclesCleared: s.cleared, obstaclesTotal: s.total, obstacleName: s.obstacleName,
                                              bestLap: s.bestLap, smoothness: s.smoothness, completed: s.completed))
            }
        }
        game?.stop()
        game = nil
        gameStatus = nil
        gameStats = []
        pedalLevel = nil
        learnTip = nil
    }

    private func advance() {
        index += 1
        if index >= items.count { finish() } else { beginIntro() }
    }

    private func finish() {
        endGame()
        phase = .summary
        rebuildEnvironment()
        coach.play(exercise: "idle")
        SoundManager.shared.play("sfx_levelup", volume: 0.8)
        SoundManager.shared.say("Session complete. \(ClinicalEngine.encouragement(stage: stage, profile: profile)) Look around: every session grows a new lotus in your recovery garden.")
        Task { await growGarden() }
    }

    /// Recovery garden: one glowing lotus per completed session floats around the person (like a progress ring
    /// you can stand inside). The newest one blooms last.
    private func growGarden() async {
        garden.removeFromParent()
        garden = Entity(); garden.name = "RecoveryGarden"
        world.addChild(garden)
        let total = min(40, AppModel.shared.state.sessions.count + 1)
        guard let lotus = try? await Entity(named: "Lotus", in: .main) else { return }
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        let sparkles = Sparkles(); garden.addChild(sparkles.root)
        for i in 0..<total {
            let ring = Float(i / 14)
            let a = Float(i % 14) / 14 * 2 * .pi + ring * 0.22
            let r: Float = 1.5 + ring * 0.6
            let l = lotus.clone(recursive: true)
            l.position = c + [sin(a) * r, 0.02, -cos(a) * r]
            l.scale = [0.01, 0.01, 0.01]
            garden.addChild(l)
            let finalScale: Float = i == total - 1 ? 1.8 : 1.2
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120 * i))
                var t: Float = 0
                while t < 1 { t += 0.06; let s = finalScale * (1 - pow(1 - min(1, t), 3)); l.scale = [s, s, s]; try? await Task.sleep(for: .milliseconds(16)) }
                if i == total - 1 {
                    sparkles.burst(at: l.position + [0, 0.15, 0], color: Palette.gold, count: 36, speed: 1.1)
                    SoundManager.shared.play("sfx_chime", volume: 0.8)
                }
            }
        }
    }

    private func broadcastLive() {
        let phaseText: String
        switch phase {
        case .safety, .scan: phaseText = "Getting ready"
        case .intro: phaseText = "Watching the demo"
        case .countdown: phaseText = "Starting"
        case .active: phaseText = "Exercising · set \(setNumber)/\(dosage?.sets ?? 1)"
        case .rest: phaseText = "Resting"
        case .painCheck: phaseText = "Pain check"
        case .summary: phaseText = "Finished"
        case .stopped: phaseText = "Stopped"
        }
        RehabTogether.shared.broadcast(LiveSessionState(exercise: exercise?.title ?? "Session", phase: phaseText, reps: reps,
                                                        secondsLeft: Int(remaining), pain: phase == .summary ? painAfter : nil,
                                                        steadiness: Int(liveSteadiness * 100)))
    }

    /// Gentle floor effect at the person's feet for each rep or landing, in the scene's style. It also works in
    /// "My room": the effect appears on the real floor.
    private func stepEffect(strength: Float) {
        if reactor?.kind != environment {
            reactor?.clear(); reactor?.root.removeFromParent()
            let r = WorldReactor(environment); world.addChild(r.root); reactor = r
        }
        let feet = SIMD3<Float>(tracker.head.x, 0, tracker.head.z) + forward * 0.15
        reactor?.react(at: feet, strength: strength, colorIndex: reps % 3)
        butterfly.celebrate(color: reactorColor)
    }

    private var reactorColor: UIColor {
        let c = WorldReactor.colors(environment)
        return c[reps % c.count]
    }

    /// Where Lumi goes in each part of the session.
    private func updateButterfly(dt: Float) {
        guard butterflyOn else { return }
        let f = tracker.headForward
        let flat = simd_normalize(SIMD3<Float>(f.x, 0, f.z) + [0, 0, -1e-4])
        let right = simd_normalize(simd_cross(flat, [0, 1, 0]))
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        let eye = max(1.1, tracker.head.y)
        let anchorForward = placed ? forward : flat
        var hand: SIMD3<Float>? = nil
        butterfly.allowsHand = phase != .active
        var handFlat: Float = 1
        if butterfly.allowsHand {
            // either hand: the higher, flatter palm is the one being offered
            let palm: (spot: SIMD3<Float>, flatness: Float)? = {
                switch (tracker.rightPalm, tracker.leftPalm) {
                case let (r?, l?): return (r.spot.y + r.flatness * 0.1) >= (l.spot.y + l.flatness * 0.1) ? r : l
                case let (r?, nil): return r
                case let (nil, l?): return l
                default: return nil
                }
            }()
            hand = palm?.spot; handFlat = palm?.flatness ?? 1
        }
        switch phase {
        case .safety:
            butterfly.mode = .hover(c + anchorForward * 1.0 + [0, eye - 0.15, 0] - right * 0.15)
        case .scan:
            butterfly.mode = .circle(c + [0, eye - 0.35, 0], 1.1)
        case .intro:
            let cr = simd_normalize(simd_cross(SIMD3<Float>(c.x - coach.root.position.x, 0, c.z - coach.root.position.z) + [0, 0, 1e-4], [0, 1, 0]))
            butterfly.mode = .perch(coach.root.position + [0, 1.5, 0] + cr * 0.2)     // on the coach's shoulder
        case .countdown:
            butterfly.mode = .hover(c + anchorForward * 1.4 + [0, eye - 0.05, 0])
        case .active:
            if let g = game, let p = g.guidePoint {
                butterfly.mode = .guide(p)                                           // shows the next pad / stone
            } else if case .game(.ballCatch)? = exercise?.kind {
                butterfly.mode = .hover(c + anchorForward * 1.2 - right * 0.7 + [0, eye + 0.15, 0])   // out of the ball's path
            } else if exercise?.seated ?? false {
                butterfly.mode = .hover(c + anchorForward * 0.7 + [0, 0.45, 0])     // near the foot, so eyes follow the ankle
            } else {
                butterfly.mode = .hover(c + anchorForward * 1.5 + [0, eye - 0.1, 0]) // fixed point to rest the eyes on for balance
            }
        case .rest:
            butterfly.mode = .breathe(c + anchorForward * 1.0 + [0, eye - 0.25, 0])
        case .painCheck:
            if let h = hud { butterfly.mode = .perch(h.position + [-0.28, 0.3, 0]) }
        case .stopped:
            butterfly.mode = .land(c + anchorForward * 0.9 + right * 0.2)
        case .summary:
            butterfly.mode = .circle(c + [0, 0.6, 0], 1.5)                           // drifts over the recovery garden
        }
        butterfly.update(dt: dt, time: clock, head: tracker.head, headForward: f, hand: hand, handFlatness: handFlat)
    }

    /// Tap Lumi for a kind word.
    func tapButterfly() {
        butterfly.celebrate(color: Brand.lilac)
        SoundManager.shared.play("sfx_shimmer", volume: 0.5)
        SoundManager.shared.say(ButterflyGuide.tapLine(seed: Int(clock)), interrupt: true)
    }

    var nextExercise: Exercise? { items.indices.contains(index + 1) ? items[index + 1].exercise : nil }

    func handleTap(_ e: Entity) {
        if butterfly.contains(e) { tapButterfly(); return }
        _ = game?.handleTap(e)
    }

    func record() -> SessionRecord {
        var s = SessionRecord(stage: stage)
        s.date = started
        s.results = results
        s.painBefore = painBefore
        s.painAfter = painAfter
        s.duration = Date().timeIntervalSince(started)
        if case .stopped(let r) = phase { s.stoppedEarly = true; s.stopReason = r.rawValue }
        if results.contains(where: { $0.painDuring ?? 0 >= 6 }) { s.stoppedEarly = true }
        return s
    }

    func tearDown() {
        endGame()
        scanner.stop()
        tracker.stop()
        SoundManager.shared.stopAll()
        world.removeFromParent()
    }

    var totalReps: Int { results.reduce(0) { $0 + $1.reps } }
    var averageSteadiness: Double? {
        let s = results.compactMap(\.steadiness)
        return s.isEmpty ? nil : s.reduce(0, +) / Double(s.count)
    }
}
