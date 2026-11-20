import RealityKit
import SwiftUI
import UIKit
import simd
import ImageIO

/// Return to Sport: the life-size coach demonstrates a sport drill with the correct technique, in an immersive
/// basketball court (Sunset Court) or in the person's own room. Footwork targets light up on the floor in rhythm,
/// Lumi flies ahead to the next target, and the ball arcs into the hoop at the end of each rep.
/// Safety is the same as in sessions: STOP is always reachable, a fall-like head drop stops everything,
/// and a pain check follows every set.
@MainActor
@Observable
final class SportLabController {
    enum Phase: Equatable {
        case watch                 // coach demonstrates on a loop, technique explained
        case countdown(Int)
        case active                // the person copies the drill, reps counted per cycle
        case rest
        case painCheck
        case done
        case stopped(String)
    }

    // configuration
    let profile: PatientProfile
    let stage: RehabStage
    let drills: [SportDrill]                // drills open today
    var drill: SportDrill
    var onCourt: Bool                       // Sunset Court (full immersion) or the person's room (mixed)
    var butterflyOn: Bool

    // state shown in the panel
    private(set) var phase: Phase = .watch
    private(set) var setNumber = 1
    private(set) var reps = 0
    private(set) var techniqueIndex = 0
    var painDuring = 0
    private(set) var results: [ExerciseResult] = []
    var restLeft = 0

    // scene
    let world = Entity()
    let coach = CoachRig()
    let butterfly = ButterflyGuide()
    let tracker = MotionTracker()
    private let sparkles = Sparkles()
    private let stageRoot = Entity()            // everything placed relative to the person (local -Z = forward)
    private var court: Entity?
    private var hoop: Entity?
    private var ball: ModelEntity?
    private var markEntities: [ModelEntity] = []
    var hud: Entity?
    var stopOrb: Entity?

    // timing
    private var clock: Double = 0
    private var cycleClock: Double = 0
    private var phaseClock: Double = 0
    private var lastMarkLit = -1
    private var ballFlight: (start: SIMD3<Float>, end: SIMD3<Float>, t: Float)?
    private var started = Date()
    private var placed = false

    // court geometry (matches the painted panorama: the person stands on the free-throw line)
    static let rimCentre = SIMD3<Float>(0, 3.05, -4.225)
    static let roomTarget = SIMD3<Float>(0, 1.9, -2.6)

    init(profile: PatientProfile, stage: RehabStage, drills: [SportDrill], first: SportDrill, onCourt: Bool, settings: AppSettings) {
        self.profile = profile
        self.stage = stage
        self.drills = drills
        self.drill = first
        self.onCourt = onCourt
        self.butterflyOn = settings.butterfly ?? true
        // Sport Lab always uses Maya: the sport clips (set shot, badminton footwork) are built and checked on her rig.
        coach.coach = .fitness
        coach.mirror = settings.mirrorCoach
        coach.injured = profile.side
    }

    var cycleLength: Double { (drill.marks.map(\.beat).max() ?? 0) + (drill.ballToHoop ? 2.6 : 1.6) }
    var dosageText: String { drill.dosage.text }

    // MARK: Setup

    func setUp() async {
        world.name = "SportLabWorld"
        world.addChild(stageRoot)
        stageRoot.addChild(sparkles.root)
        await coach.load()
        coach.root.position = [-0.9, 0, -2.3]
        coach.root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.7, 1.8, 0.5]).offsetBy(translation: [0, 0.9, 0])]))
        coach.root.components.set(InputTargetComponent())
        stageRoot.addChild(coach.root)
        butterfly.visible = butterflyOn
        butterfly.place(at: [0.3, 1.4, -1.1])
        world.addChild(butterfly.node)
        buildMarks()
        buildBall()
        rebuildPlace()
        coach.play(exercise: drill.clip)
        Task { @MainActor in await self.tracker.start() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            self.placeScene()
        }
        SoundManager.shared.say("Welcome to Sport Lab. \(onCourt ? "This is Sunset Court." : "We'll train right here in your room.") Watch me first. \(drill.title). \(drill.technique.first ?? "")")
    }

    private func placeScene() {
        tracker.update()
        let f = tracker.headForward
        let c = SIMD3<Float>(tracker.head.x, 0, tracker.head.z)
        stageRoot.position = c
        stageRoot.orientation = yawToward(f)
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        hud?.position = c + f * 1.25 + right * 0.62 + [0, max(1.15, tracker.head.y - 0.22), 0]
        hud?.orientation = yawToward(f)
        stopOrb?.position = c + f * 0.7 - right * 0.36 + [0, max(1.0, tracker.head.y - 0.42), 0]
        stopOrb?.orientation = yawToward(f)
        tracker.calibrate()
        placed = true
    }

    func tearDown() {
        tracker.stop()
        SoundManager.shared.stopAll()
    }

    /// Court (full immersion) or room (mixed): built from the same painted 360° panorama as the other scenes.
    func rebuildPlace() {
        court?.removeFromParent(); court = nil
        hoop?.removeFromParent(); hoop = nil
        if onCourt {
            // Badminton drills get their own court (owner feedback 28 Oct: a lunge on a basketball court looked wrong).
            let isBadminton = drill.sport == .badminton
            let e = Self.makeCourt(withModel: !isBadminton)
            if isBadminton { e.addChild(Self.makeBadmintonCourt()) }
            stageRoot.addChild(e); court = e
            if !Self.hasCourtModel && !isBadminton {                     // the 3D court brings its own regulation hoop
                let h = Self.makeHoop()
                stageRoot.addChild(h); hoop = h
            }
            // Light the coach and the ball with the court's sky light, plus a soft key light from the front, so both
            // read clearly against the court.
            let key = Entity(); key.name = "CoachKeyLight"
            key.components.set(SpotLightComponent(color: UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), intensity: 90_000,
                                                  innerAngleInDegrees: 30, outerAngleInDegrees: 60, attenuationRadius: 12))
            e.addChild(key)
            key.look(at: coach.root.position + [0, 1.1, 0], from: [0.6, 3.4, 0.4], relativeTo: e)
            Task { @MainActor [weak self, weak e] in
                for _ in 0..<50 {
                    if let ibl = e?.findEntity(named: "CourtIBL") {
                        self?.stageRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                        if let c = self?.coach.root { Self.applyIBL(ibl, to: c) }
                        if let b = self?.ball { b.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl)) }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            SoundManager.shared.startAmbience("amb_meadow")
        } else {
            let ring = Self.makeTargetRing()
            ring.position = Self.roomTarget
            stageRoot.addChild(ring); hoop = ring
            SoundManager.shared.stopAmbience()
        }
    }

    func setOnCourt(_ v: Bool) {
        guard v != onCourt else { return }
        onCourt = v
        rebuildPlace()
        SoundManager.shared.say(v ? "Sunset Court." : "Here's your room. Keep the floor around you clear.", interrupt: true)
    }

    func choose(_ d: SportDrill) {
        guard d.id != drill.id else { return }
        let sportChanged = d.sport != drill.sport
        drill = d
        if sportChanged && onCourt { rebuildPlace() }
        setNumber = 1; reps = 0; techniqueIndex = 0; cycleClock = 0; lastMarkLit = -1; shotFired = false
        if shotPoints != nil { coach.restart() }
        phase = .watch
        buildMarks()
        coach.play(exercise: d.clip, transition: 0.3)
        SoundManager.shared.say("\(d.title). Watch me first. \(d.technique.first ?? "")", interrupt: true)
    }

    // MARK: Flow

    func startPractice() {
        phase = .countdown(3); phaseClock = 0
        SoundManager.shared.say("Your turn. Three, two, one.", interrupt: true)
    }

    func finishSet() {
        phase = .painCheck
        coach.play(exercise: "idle", transition: 0.3)
        SoundManager.shared.say("Set done. How does the ankle feel right now?", interrupt: true)
        if butterflyOn { butterfly.mode = .perch((hud?.position ?? [0.6, 1.3, -1.2]) + [0, 0.32, 0]) }
    }

    func submitPain(_ p: Int) {
        painDuring = p
        switch ClinicalEngine.zone(p) {
        case .red:
            stop("Pain went to \(p)/10. Rest, ice in short sessions and elevate. If it doesn't settle, see your physio.")
            return
        case .amber:
            SoundManager.shared.say("Thanks. We'll keep it easier. One more set at most today.", interrupt: true)
        case .green:
            SoundManager.shared.say("Great. Breathe with Lumi.", interrupt: true)
        }
        let limit = ClinicalEngine.zone(p) == .amber ? min(drill.dosage.sets, setNumber + 1) : drill.dosage.sets
        if setNumber >= limit {
            complete()
        } else {
            setNumber += 1; reps = 0
            phase = .rest; restLeft = drill.dosage.restSeconds; phaseClock = 0
            if butterflyOn { butterfly.mode = .breathe(stageRoot.position + forward * 0.9 + [0, 1.35, 0]) }
        }
    }

    private func complete() {
        phase = .done
        coach.play(exercise: "idle", transition: 0.3)
        SoundManager.shared.play("sfx_levelup")
        SoundManager.shared.say("Brilliant work. That's how you move back toward your sport, one controlled rep at a time.", interrupt: true)
        results.append(ExerciseResult(exerciseID: drill.id, setsDone: setNumber, setsTarget: drill.dosage.sets, reps: reps, painDuring: painDuring))
    }

    func stop(_ why: String = "You stopped.") {
        if case .stopped = phase { return }
        SoundManager.shared.stopVoice()
        SoundManager.shared.play("sfx_stop")
        coach.play(exercise: "idle", transition: 0.2)
        phase = .stopped(why)
        ballFlight = nil; ball?.isEnabled = false
        markEntities.forEach { $0.isEnabled = false }
        if butterflyOn { butterfly.mode = .land(stageRoot.position + forward * 0.6) }
        SoundManager.shared.say("Stopped. Take a breath. If anything feels wrong, call your physio or NurseFirst on 6262 6262. In an emergency, call 995.")
    }

    /// Session record for Progress (each drill done counts like a plan exercise).
    func record(into model: AppModel) {
        guard !results.isEmpty else { return }
        var r = SessionRecord(stage: stage)
        r.results = results
        r.painBefore = model.latestPain
        r.painAfter = painDuring
        r.duration = Date().timeIntervalSince(started)
        if case .stopped(let why) = phase { r.stoppedEarly = true; r.stopReason = why }
        model.record(session: r)
        results.removeAll()
    }

    var forward: SIMD3<Float> { stageRoot.orientation.act([0, 0, -1]) }

    // MARK: Per-frame

    func tick(dt: Float) {
        clock += Double(dt)
        tracker.update()
        sparkles.update(dt: dt)
        // In drills that end with a shot, the coach faces the hoop (you copy her from behind); otherwise she faces you.
        coach.root.orientation = drill.ballToHoop ? simd_quatf(angle: .pi, axis: [0, 1, 0]) : simd_quatf(angle: 0, axis: [0, 1, 0])
        coach.tick(time: clock)
        if case .stopped = phase {} else if case .done = phase {} else {
            if tracker.fallLike(hopping: drill.requiresHopClearance) { stop("It looked like you lost balance, so we stopped.") }
        }
        switch phase {
        case .watch, .active:
            runCycle(dt: Double(dt), counting: phase == .active)
        case .countdown(let n):
            phaseClock += Double(dt)
            if phaseClock >= 1 {
                phaseClock = 0
                if n > 1 { phase = .countdown(n - 1); SoundManager.shared.play("sfx_tick") }
                else {
                    phase = .active; cycleClock = 0; lastMarkLit = -1; shotFired = false
                    if shotPoints != nil { coach.restart() }
                    SoundManager.shared.play("sfx_go")
                }
            }
        case .rest:
            phaseClock += Double(dt)
            if phaseClock >= 1 { phaseClock = 0; restLeft -= 1 }
            if restLeft <= 0 { startPractice() }
        default: break
        }
        updateBall(dt: dt)
        updateButterfly(dt: dt)
    }

    private func runCycle(dt: Double, counting: Bool) {
        cycleClock += dt
        // light the footwork targets in rhythm
        for (i, m) in drill.marks.enumerated() where i > lastMarkLit && cycleClock >= m.beat {
            lastMarkLit = i
            flash(i)
            if butterflyOn, i + 1 < drill.marks.count {
                let n = drill.marks[i + 1]
                butterfly.mode = .guide(worldPoint([n.x, 0, n.z]) + [0, 0.35, 0])
            }
            if i == 0 && !counting && !drill.technique.isEmpty {
                techniqueIndex = (techniqueIndex + 1) % drill.technique.count
                SoundManager.shared.say(drill.technique[techniqueIndex])
            }
        }
        // Set shot: the ball sits in the coach's hands (it follows the hand joints of the animation), and leaves them
        // once per rep when the clip reaches its release time. The release is an event (fired once per cycle), so a
        // slow frame can never skip the throw.
        let release = shotPoints.map { $0.releaseTime } ?? (cycleLength - 2.2)
        if drill.ballToHoop && !shotFired && cycleClock >= release {
            shotFired = true
            shoot()
        }
        if drill.ballToHoop, ballFlight == nil, let sp = shotPoints, let ball {
            let held = !shotFired || cycleClock > 2.3
            ball.isEnabled = held
            if held {
                ball.position = heldBallPosition(sp)
                ball.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            }
        }
        if cycleClock >= cycleLength {
            cycleClock = 0; lastMarkLit = -1; shotFired = false
            if shotPoints != nil { coach.restart() }        // keep the shot in step with the rep cycle
            markEntities.forEach { setMark($0, lit: false) }
            if counting {
                reps += 1
                SoundManager.shared.play("sfx_success", volume: 0.6)
                butterfly.celebrate(color: Brand.peach)
                bloom(at: drill.marks.last.map { SIMD3<Float>($0.x, 0, $0.z) } ?? .zero)
                let target = drill.dosage.reps ?? 5
                if reps >= target { finishSet() }
                else if reps == target - 1 { SoundManager.shared.say("Last one.") }
            }
        }
    }

    // MARK: Footwork targets

    private func buildMarks() {
        markEntities.forEach { $0.removeFromParent() }
        markEntities = drill.marks.map { m in
            let mesh = EnvironmentBuilder.annulus(inner: 0.13, outer: 0.17) ?? .generatePlane(width: 0.3, depth: 0.3)
            let e = ModelEntity(mesh: mesh, materials: [EnvironmentBuilder.glow(m.hop ? Brand.peach : Brand.dawnBlue, opacity: 0.35)])
            e.position = [m.x, 0.006, m.z]
            stageRoot.addChild(e)
            return e
        }
    }

    private func setMark(_ e: ModelEntity, lit: Bool) {
        let i = markEntities.firstIndex { $0 === e } ?? 0
        let hop = i < drill.marks.count ? drill.marks[i].hop : false
        e.model?.materials = [EnvironmentBuilder.glow(lit ? Brand.cream : (hop ? Brand.peach : Brand.dawnBlue), opacity: lit ? 0.95 : 0.35)]
        e.scale = lit ? [1.25, 1, 1.25] : [1, 1, 1]
    }

    private func flash(_ i: Int) {
        guard i < markEntities.count else { return }
        markEntities.forEach { setMark($0, lit: false) }
        setMark(markEntities[i], lit: true)
        SoundManager.shared.play(footSound(i), volume: 0.5)
        if drill.id == "bd_front_lunge" && i == 1 { SoundManager.shared.play("sfx_shuttle_hit", volume: 0.6) }
        sparkles.burst(at: markEntities[i].position + [0, 0.02, 0], color: Brand.cream, count: 8, speed: 0.35, size: 0.006)
    }

    /// What the foot sounds like on this mark: court-shoe squeaks for basketball footwork, a heel-first landing
    /// for the badminton lunge and split step, a soft tap otherwise.
    private func footSound(_ i: Int) -> String {
        let m = drill.marks[i]
        switch drill.sport {
        case .badminton: return (m.hop || (drill.id == "bd_front_lunge" && i == 1)) ? "sfx_lunge_land" : "sfx_tap"
        case .basketball: return m.hop ? "sfx_lunge_land" : (drill.id == "bb_defensive_slide" ? "sfx_sneaker" : "sfx_tap")
        default: return m.hop ? "sfx_drop" : "sfx_tap"
        }
    }

    /// The Steady brand bloom: a soft pool of light and a few drifting motes where the foot lands.
    private func bloom(at local: SIMD3<Float>) {
        sparkles.burst(at: local + [0, 0.03, 0], color: Brand.amber, count: 14, speed: 0.5, size: 0.008)
    }

    private func worldPoint(_ local: SIMD3<Float>) -> SIMD3<Float> { stageRoot.convert(position: local, to: nil) }

    // MARK: Ball

    private func buildBall() {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.95, green: 0.42, blue: 0.13, alpha: 1))
        m.roughness = .init(floatLiteral: 0.65)
        let b = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [m])
        // seams
        for a in [Float(0), .pi / 2] {
            let seam = ModelEntity(mesh: .generateBox(size: [0.245, 0.006, 0.006]), materials: [UnlitMaterial(color: UIColor(white: 0.1, alpha: 1))])
            seam.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            b.addChild(seam)
        }
        b.isEnabled = false
        stageRoot.addChild(b)
        ball = b
    }

    /// Ball points of the set-shot clip (only when the drill uses it and the coach file has them).
    private var shotPoints: (hold: SIMD3<Float>, release: SIMD3<Float>, releaseTime: Double)? {
        guard drill.clip == "set_shot", let s = coach.manifest?.shot, s.hold.count == 3, s.release.count == 3 else { return nil }
        return (SIMD3(s.hold[0], s.hold[1], s.hold[2]), SIMD3(s.release[0], s.release[1], s.release[2]), s.releaseTime)
    }

    @ObservationIgnored private var shotFired = false
    @ObservationIgnored private var makes = 0
    @ObservationIgnored private var bounced = false

    /// Where the held ball is: between the coach's animated hands, or the clip's baked hold point as a fallback.
    private func heldBallPosition(_ sp: (hold: SIMD3<Float>, release: SIMD3<Float>, releaseTime: Double)) -> SIMD3<Float> {
        if let w = coach.handsWorldPosition() { return stageRoot.convert(position: w, from: nil) }
        return coach.root.convert(position: sp.hold, to: stageRoot)
    }

    private func shoot() {
        let hands: SIMD3<Float>
        if let sp = shotPoints {
            hands = coach.handsWorldPosition().map { stageRoot.convert(position: $0, from: nil) }
                ?? coach.root.convert(position: sp.release, to: stageRoot)
        } else {
            hands = coach.root.position + [0.15, 1.9, 0.1]
        }
        let target = onCourt ? Self.rimCentre : Self.roomTarget
        ballFlight = (hands, target, 0)
        bounced = false
        SoundManager.shared.play("sfx_bb_release", volume: 0.5)
        ball?.position = hands
        ball?.isEnabled = true
    }

    private func updateBall(dt: Float) {
        guard var f = ballFlight, let ball else { return }
        f.t += dt / 1.15
        let t = min(f.t, 1)
        let apex: Float = onCourt ? 1.3 : 0.6
        var p = f.start + (f.end - f.start) * t
        p.y += apex * 4 * t * (1 - t)
        ball.position = p
        ball.orientation = simd_quatf(angle: -t * 9, axis: [1, 0, 0])
        if f.t >= 1 {
            // through the net, then a real fall to the court and one bounce
            let fall = (f.t - 1) * 1.15
            let y = f.end.y - 0.5 * 9.8 * fall * fall
            if f.t - dt / 1.15 < 1 {
                makes += 1
                if makes % 3 == 0 { SoundManager.shared.play("sfx_bb_rim", volume: 0.35) }   // the odd soft rim touch
                SoundManager.shared.play("sfx_bb_swish", volume: 0.7)
                sparkles.burst(at: f.end, color: Brand.firefly, count: 12, speed: 0.4, size: 0.008)
            }
            if y <= 0.12 {
                if !bounced { bounced = true; SoundManager.shared.play("sfx_bb_bounce", volume: onCourt ? 0.7 : 0.45) }
                ball.isEnabled = false; ballFlight = nil; return
            }
            ball.position = [f.end.x, y, f.end.z + fall * 0.15]
        }
        ballFlight = f
    }

    // MARK: Lumi

    private func updateButterfly(dt: Float) {
        guard butterflyOn else { return }
        butterfly.allowsHand = phase != .active
        switch phase {
        case .watch:
            if case .guide = butterfly.mode {} else { butterfly.mode = .hover(tracker.head + tracker.headForward * 1.2 + [0, -0.1, 0]) }
        case .done:
            butterfly.mode = .hover(tracker.head + tracker.headForward * 1.0)
        default: break
        }
        let hand = (tracker.rightPalm ?? tracker.leftPalm)?.spot
        butterfly.update(dt: dt, time: clock, head: tracker.head, headForward: tracker.headForward, hand: hand)
    }

    func handleTap(_ e: Entity) {
        if butterfly.contains(e) {
            butterfly.celebrate(color: Brand.lilac)
            SoundManager.shared.say(ButterflyGuide.tapLine(seed: Int(clock)), interrupt: true)
        }
    }

    // MARK: Builders

    static var hasCourtModel: Bool { Bundle.main.url(forResource: "Court", withExtension: "usdz") != nil }

    /// Sunset Court: a real 3D outdoor court ("Basketball Court" by Klieg3D, CC BY 4.0, rim 3.05 m, near rim on
    /// `rimCentre`) under a photographed sunset sky (Poly Haven "Belfast Sunset (Pure Sky)", CC0, 8K), lit by that sky.
    /// `withModel: false` gives just the sky, ground and light (Play Smart brings its own court in Court3D).
    /// Falls back to the painted panorama if the new files are missing.
    static func makeCourt(withModel: Bool = true) -> Entity {
        let root = Entity(); root.name = "SunsetCourt"
        guard let sky = Bundle.main.url(forResource: "env_court_sky", withExtension: "jpg"),
              let tex = try? TextureResource.load(contentsOf: sky) else { return makePaintedCourt() }
        var mat = UnlitMaterial(); mat.color = .init(tint: .white, texture: .init(tex))
        if let mesh = EnvironmentBuilder.patch(radius: 60, azSpan: 360, elMin: -8, elMax: 90, azSteps: 160, elSteps: 64, imageElMin: -8) {
            let e = ModelEntity(mesh: mesh, materials: [mat]); e.position = [0, 1.6, 0]
            root.addChild(e)
        }
        // open ground beyond the fence, in the colour of the haze at the horizon so it melts into the sky
        var gm = PhysicallyBasedMaterial()
        gm.baseColor = .init(tint: UIColor(red: 0.36, green: 0.34, blue: 0.36, alpha: 1)); gm.roughness = .init(floatLiteral: 0.95)
        let ground = ModelEntity(mesh: .generatePlane(width: 160, depth: 160), materials: [gm]); ground.position.y = -0.02
        root.addChild(ground)
        // warm low sun from the sunset side plus soft sky light
        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: UIColor(red: 1.0, green: 0.86, blue: 0.7, alpha: 1), intensity: 4200))
        sun.look(at: [0, 0, -2], from: [5, 6, 4], relativeTo: nil)
        root.addChild(sun)
        let lightURL = Bundle.main.url(forResource: "env_court_light", withExtension: "jpg")
        Task { @MainActor in
            var iblEntity: Entity?
            if let lightURL, let src = CGImageSourceCreateWithURL(lightURL as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
               let env = try? await EnvironmentResource(equirectangular: img) {
                let ibl = Entity(); ibl.name = "CourtIBL"
                ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.8))
                root.addChild(ibl)
                root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                ground.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
                iblEntity = ibl
            }
            if withModel, let court = try? await Entity(named: "Court", in: .main) {
                if let ibl = iblEntity { applyIBL(ibl, to: court) }
                root.addChild(court)
            }
        }
        return root
    }

    /// A regulation badminton court (BWF Laws of Badminton: 13.40 × 6.10 m, lines 40 mm, net 1.55 m at the posts and
    /// 1.524 m at the centre). The person and the coach stand on the near half; the net is 4 m ahead.
    static func makeBadmintonCourt() -> Entity {
        let root = Entity(); root.name = "BadmintonCourt"
        let netZ: Float = -4.0, half: Float = 6.70, w: Float = 6.10
        let near = netZ + half, far = netZ - half
        func pbr(_ c: UIColor, rough: Float = 0.85) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial(); m.baseColor = .init(tint: c); m.roughness = .init(floatLiteral: rough); return m
        }
        // run-off floor and the green playing surface (sports vinyl colours)
        let runoff = ModelEntity(mesh: .generatePlane(width: w + 4, depth: half * 2 + 5), materials: [pbr(UIColor(red: 0.18, green: 0.32, blue: 0.30, alpha: 1))])
        runoff.position = SIMD3<Float>(0, 0.002, netZ); root.addChild(runoff)
        let surface = ModelEntity(mesh: .generatePlane(width: w, depth: half * 2), materials: [pbr(UIColor(red: 0.13, green: 0.45, blue: 0.36, alpha: 1))])
        surface.position = SIMD3<Float>(0, 0.004, netZ); root.addChild(surface)
        // lines
        let white = pbr(.white, rough: 0.7), lw: Float = 0.04
        func line(x0: Float, z0: Float, x1: Float, z1: Float) {
            let len = max(abs(x1 - x0), abs(z1 - z0)) + lw
            let alongX = abs(x1 - x0) > abs(z1 - z0)
            let e = ModelEntity(mesh: .generateBox(width: alongX ? len : lw, height: 0.003, depth: alongX ? lw : len), materials: [white])
            e.position = SIMD3<Float>((x0 + x1) / 2, 0.007, (z0 + z1) / 2); root.addChild(e)
        }
        let hw = w / 2, singles = hw - 0.46
        for x in [-hw, hw, -singles, singles] { line(x0: x, z0: near, x1: x, z1: far) }          // side lines
        for z in [near, far, near - 0.76, far + 0.76, netZ + 1.98, netZ - 1.98] {                  // back, long service, short service
            line(x0: -hw, z0: z, x1: hw, z1: z)
        }
        line(x0: 0, z0: netZ + 1.98, x1: 0, z1: near); line(x0: 0, z0: netZ - 1.98, x1: 0, z1: far)  // centre lines
        // posts and net
        let post = pbr(UIColor(white: 0.92, alpha: 1), rough: 0.4)
        for x in [-hw, hw] {
            let p = ModelEntity(mesh: .generateCylinder(height: 1.55, radius: 0.02), materials: [post])
            p.position = SIMD3<Float>(x, 0.775, netZ); root.addChild(p)
        }
        var mesh = PhysicallyBasedMaterial(); mesh.baseColor = .init(tint: UIColor(white: 0.08, alpha: 1))
        mesh.blending = .transparent(opacity: .init(floatLiteral: 0.45)); mesh.faceCulling = .none
        let net = ModelEntity(mesh: .generatePlane(width: w, height: 0.76), materials: [mesh])
        net.position = SIMD3<Float>(0, 1.144, netZ); root.addChild(net)
        let tape = ModelEntity(mesh: .generateBox(width: w, height: 0.075, depth: 0.01), materials: [pbr(.white, rough: 0.6)])
        tape.position = SIMD3<Float>(0, 1.4865, netZ); root.addChild(tape)
        return root
    }

    static func applyIBL(_ ibl: Entity, to e: Entity) {
        e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for c in e.children { applyIBL(ibl, to: c) }
    }

    /// The original painted Sunset Court panorama (used only if the 3D court files are missing).
    static func makePaintedCourt() -> Entity {
        let root = Entity(); root.name = "SunsetCourt"
        guard let u = Bundle.main.url(forResource: "env_sunset_court_ground", withExtension: "jpg")
                ?? Bundle.main.url(forResource: "env_sunset_court", withExtension: "jpg"),
              let tex = try? TextureResource.load(contentsOf: u) else { return root }
        var mat = UnlitMaterial(); mat.color = .init(tint: .white, texture: .init(tex))
        if let mesh = EnvironmentBuilder.patch(radius: 40, azSpan: 360, elMin: -90, elMax: 90, azSteps: 96, elSteps: 48) {
            let e = ModelEntity(mesh: mesh, materials: [mat]); e.position = [0, 1.6, 0]
            root.addChild(e)
        }
        if let g = EnvironmentBuilder.groundFromPanorama(radius: 30) {
            var gm = UnlitMaterial(); gm.color = .init(tint: .white, texture: .init(tex))
            let ground = ModelEntity(mesh: g, materials: [gm]); ground.position.y = -0.003
            root.addChild(ground)
        }
        return root
    }

    /// Regulation hoop (rim 3.05 m) at the painted court's basket position.
    static func makeHoop() -> Entity {
        let root = Entity(); root.name = "Hoop"
        let dark = SimpleMaterial(color: UIColor(red: 0.16, green: 0.18, blue: 0.27, alpha: 1), isMetallic: true)
        let white = UnlitMaterial(color: UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1))
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(white: 1, alpha: 1)); glass.roughness = .init(floatLiteral: 0.05)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        let boardZ: Float = -4.6
        let pole = ModelEntity(mesh: .generateBox(size: [0.16, 3.6, 0.16]), materials: [dark]); pole.position = [0, 1.8, -6.8]
        let arm = ModelEntity(mesh: .generateBox(size: [0.12, 0.12, 2.2]), materials: [dark]); arm.position = [0, 3.45, -5.7]
        let board = ModelEntity(mesh: .generateBox(size: [1.8, 1.05, 0.03]), materials: [glass]); board.position = [0, 3.425, boardZ]
        root.addChild(pole); root.addChild(arm); root.addChild(board)
        // white frame and shooter's square
        let parts: [([Float], [Float])] = [([1.8, 0.05, 0.035], [0, 3.925, boardZ]), ([1.8, 0.05, 0.035], [0, 2.925, boardZ]),
                            ([0.05, 1.05, 0.035], [-0.875, 3.425, boardZ]), ([0.05, 1.05, 0.035], [0.875, 3.425, boardZ]),
                            ([0.59, 0.05, 0.035], [0, 3.47, boardZ]), ([0.05, 0.45, 0.035], [-0.295, 3.27, boardZ]),
                            ([0.05, 0.45, 0.035], [0.295, 3.27, boardZ])]
        for (size, pos) in parts {
            let e = ModelEntity(mesh: .generateBox(size: [size[0], size[1], size[2]]), materials: [white])
            e.position = [pos[0], pos[1], pos[2] + 0.02]
            root.addChild(e)
        }
        // rim: ring of short segments, and a soft net of cords
        let orange = SimpleMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1), isMetallic: true)
        let c = rimCentre
        let n = 28
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            let seg = ModelEntity(mesh: .generateBox(size: [0.056, 0.018, 0.018]), materials: [orange])
            seg.position = c + [sin(a) * 0.235, 0, cos(a) * 0.235]
            seg.orientation = simd_quatf(angle: a + .pi / 2, axis: [0, 1, 0])
            root.addChild(seg)
            if k % 2 == 0 {
                var net = UnlitMaterial(color: .white); net.blending = .transparent(opacity: .init(floatLiteral: 0.7))
                let cord = ModelEntity(mesh: .generateBox(size: [0.006, 0.42, 0.006]), materials: [net])
                cord.position = c + [sin(a) * 0.19, -0.21, cos(a) * 0.19]
                cord.orientation = simd_quatf(angle: 0.2, axis: simd_normalize(SIMD3<Float>(cos(a), 0, -sin(a))))
                root.addChild(cord)
            }
        }
        return root
    }

    /// In the person's room: a glowing ring target instead of a full hoop (it never pierces walls or the ceiling).
    static func makeTargetRing() -> Entity {
        let e = Entity()
        if let mesh = EnvironmentBuilder.annulus(inner: 0.2, outer: 0.24) {
            let ring = ModelEntity(mesh: mesh, materials: [EnvironmentBuilder.glow(Brand.amber, opacity: 0.85)])
            e.addChild(ring)
        }
        return e
    }
}
