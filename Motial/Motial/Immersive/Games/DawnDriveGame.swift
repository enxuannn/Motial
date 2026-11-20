import RealityKit
import UIKit
import simd

/// Dawn Drive: a glowing toy race track on the floor in front of you, like a slot-car set. Your ankle is the
/// accelerator: pointing the toes down (heel raise standing, or the Motial Pedal iPhone on the foot seated)
/// speeds the car up, lowering slowly eases it off. The skill is control, not speed: corners glow gold and need
/// you to ease off in time (eccentric control) for a "clean corner"; straights hold light orbs to collect at pace.
/// You race your own ghost (best lap). "Your ankle, live" shows the bones and muscles working beside the track.
@MainActor
final class DawnDriveGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var stats: [GameStat] {
        [GameStat(value: "\(min(lap, Self.laps))/\(Self.laps)", label: "Lap", progress: Double(min(lap, Self.laps) - 1) / Double(Self.laps)),
         GameStat(value: String(format: "%.1f s", lapTime), label: "This lap"),
         GameStat(value: "\(orbsCollected)", label: "Orbs"),
         GameStat(value: "\(cleanCorners)", label: "Clean corners"),
         GameStat(value: bestLap.map { String(format: "%.1f s", $0) } ?? "–", label: "Best lap")]
    }
    var pedalLevel: Float? { pedal.value }
    var summary: GameSummary? {
        GameSummary(orbs: orbsCollected, cleared: cleanCorners, total: cornersEntered, obstacleName: "corners",
                    bestLap: bestLap.map(Double.init), smoothness: Double(smoothN > 0 ? smoothSum / smoothN : 0), completed: lap > Self.laps)
    }
    var learnTip: String? { anatomy.tip }
    var status: String { "Lap \(min(lap, Self.laps)) of \(Self.laps) · \(orbsCollected) orbs · \(cleanCorners) clean corners" }

    private let config: GameConfig
    private var pedal: AnklePedal
    private let stage = Entity()
    private let car = Entity()
    private let ghost = Entity()
    private let anatomy = LiveAnkle()
    private let sparkles = Sparkles()
    private let audio = DriveAudio(loudness: 0.6)
    private var cornersEntered = 0
    private var smoothSum: Float = 0
    private var smoothN: Float = 0

    // track (stage-local, closed loop)
    private var pts: [SIMD3<Float>] = []
    private var cum: [Float] = []
    private var comfort: [Float] = []
    private var turn: [Float] = []           // +1 left, −1 right
    private var length: Float = 1

    // car
    private var s: Float = 0
    private var speed: Float = 0
    private var slide: Float = 0
    private var lap = 1
    static let laps = 3
    private var lapTime: Float = 0
    private var bestLap: Float?
    private var trace: [Float] = []
    private var bestTrace: [Float] = []
    private var traceTimer: Float = 0
    private var ghostClock: Float = 0

    // orbs and corners
    private struct Orb { let e: Entity; let s: Float; var taken = false; var fly: Float = 0 }
    private var orbs: [Orb] = []
    private(set) var orbsCollected = 0
    private(set) var cleanCorners = 0
    private var slides = 0
    private var inCorner = false
    private var cornerSlid = false
    private var warned = false
    private struct Ripple { let e: ModelEntity; var t: Float }
    private var ripples: [Ripple] = []
    private var t: Float = 0
    private var doneTimer: Float = 0
    private var rippleCooldown: Float = 0

    static let maxSpeed: Float = 0.62
    static let cornerSpeed: Float = 0.45
    private var bestKey: String { config.seated ? "remer.dawnDrive.bestLap.seated" : "remer.dawnDrive.bestLap" }

    init(config: GameConfig) {
        self.config = config
        self.pedal = AnklePedal(seated: config.seated)
    }

    // MARK: Setup
    func start(tracker: MotionTracker) {
        stage.position = [tracker.centre.x, 0, tracker.centre.z]
        stage.orientation = yawToward(tracker.headForward)
        root.addChild(stage)
        root.addChild(sparkles.root)
        buildTrack()
        buildRoad()
        placeOrbs()

        stage.addChild(car)
        stage.addChild(ghost)
        ghost.isEnabled = false
        Task { @MainActor in
            await self.loadCar(into: self.car, opacity: 1)
            await self.loadCar(into: self.ghost, opacity: 0.3)
        }
        let saved = UserDefaults.standard.float(forKey: bestKey)
        if saved > 0 { bestLap = saved }

        // "Your ankle, live" panel to the right of the track, turned toward the person
        let eye: Float = config.seated ? 1.0 : 1.25
        let p = SIMD3<Float>(-1.15, eye, -1.6)    // left of the track, clear of the session panel
        anatomy.root.position = p
        stage.addChild(anatomy.root)
        anatomy.root.look(at: [2 * p.x, p.y, 2 * p.z], from: p, relativeTo: stage)   // +Z face toward the person
        Task { @MainActor in await self.anatomy.load() }

        placeCar()
        audio.start()
        feedback = config.seated
            ? (pedal.demo ? "Open Motial Pedal on your iPhone, or watch the demo lap" : "Point your toes down slowly to drive")
            : (pedal.demo ? "Demo pace: watch how a slow press and slow release drives" : "Rise slowly onto your toes to drive")
        if let b = bestLap { feedback = "Your best lap: \(String(format: "%.1f", b)) s. Race your ghost" }
        ShinLink.shared.sendStatus("Dawn Drive · lap 1 of \(Self.laps)")
    }

    private func buildTrack() {
        let n = 360
        let k: Float = 0.85
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi
            let x = k * (1.3 * cos(a) + 0.22 * cos(3 * a))
            let z = k * (0.8 * sin(a) + 0.2 * sin(2 * a))
            pts.append([0.45 + x, 0.012, -3.0 + z])        // beyond the coach and a little to the right
        }
        cum = [0]
        for i in 1...n { cum.append(cum[i - 1] + simd_distance(pts[i - 1], pts[i % n])) }
        length = cum[n]
        var raw: [Float] = []
        for i in 0..<n {
            let p0 = pts[(i - 4 + n) % n], p1 = pts[i], p2 = pts[(i + 4) % n]
            let a = simd_normalize(p1 - p0), b = simd_normalize(p2 - p1)
            let ang = acos(max(-1, min(1, simd_dot(a, b))))
            let kappa = ang / max(simd_distance(p0, p1) + simd_distance(p1, p2), 1e-3)
            raw.append(min(Self.maxSpeed, sqrt(0.14 / max(kappa, 0.01))))
            turn.append(simd_cross(a, b).y >= 0 ? 1 : -1)
        }
        // smooth so corners have a lead-in
        for i in 0..<n {
            var m = raw[i]
            for d in -10...10 { m = min(m, raw[(i + d + n) % n] + abs(Float(d)) * 0.012) }
            comfort.append(m)
        }
    }

    private func index(at s: Float) -> Int {
        var u = s.truncatingRemainder(dividingBy: length)
        if u < 0 { u += length }
        var lo = 0, hi = pts.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if cum[mid] <= u { lo = mid } else { hi = mid - 1 } }
        return lo
    }

    private func frame(at s: Float) -> (p: SIMD3<Float>, tangent: SIMD3<Float>, side: SIMD3<Float>) {
        let n = pts.count
        let i = index(at: s)
        let a = pts[i], b = pts[(i + 1) % n]
        var u = s.truncatingRemainder(dividingBy: length); if u < 0 { u += length }
        let seg = max(cum[i + 1] - cum[i], 1e-4)
        let f = (u - cum[i]) / seg
        let tng = simd_normalize(b - a)
        return (a + (b - a) * f, tng, SIMD3<Float>(-tng.z, 0, tng.x))
    }

    private func ribbon(from i0: Int, to i1: Int, offset: Float, width: Float, y: Float) -> MeshResource? {
        let n = pts.count
        var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
        var k: UInt32 = 0
        for j in i0...max(i0, i1) {
            let a = pts[j % n], b = pts[(j + 1) % n]
            let tng = simd_normalize(b - a)
            let side = SIMD3<Float>(-tng.z, 0, tng.x)
            let c = a + side * offset
            pos.append(c + side * width / 2 + [0, y, 0])
            pos.append(c - side * width / 2 + [0, y, 0])
            if k > 0 { idx += [2 * k - 2, 2 * k - 1, 2 * k, 2 * k - 1, 2 * k + 1, 2 * k] }
            k += 1
        }
        guard pos.count >= 4 else { return nil }
        var md = MeshDescriptor(name: "ribbon")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: pos.count))
        md.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [md])
    }

    private func buildRoad() {
        let n = pts.count
        let w: Float = 0.3
        var road = EnvironmentBuilder.glow(UIColor(red: 0.08, green: 0.13, blue: 0.28, alpha: 1), opacity: 0.7)
        road.faceCulling = .none
        if let m = ribbon(from: 0, to: n, offset: 0, width: w, y: 0) { stage.addChild(ModelEntity(mesh: m, materials: [road])) }
        // edges: teal on straights, gold where you need to ease off
        var runStart = 0
        for i in 1...n {
            let corner = comfort[runStart % n] < Self.cornerSpeed
            let here = i < n ? comfort[i] < Self.cornerSpeed : !corner
            if here != corner || i == n {
                var mat = EnvironmentBuilder.glow(corner ? Palette.gold : Palette.teal, opacity: 0.9)
                mat.faceCulling = .none
                for off in [w / 2, -w / 2] {
                    if let m = ribbon(from: runStart, to: i, offset: off, width: 0.014, y: 0.002) {
                        stage.addChild(ModelEntity(mesh: m, materials: [mat]))
                    }
                }
                if corner {
                    // soft "ease off" glow at the corner entry
                    let f = frame(at: cum[runStart])
                    if let ring = EnvironmentBuilder.annulus(inner: 0.0, outer: 0.12) {
                        let g = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.07)])
                        g.position = f.p + [0, 0.004, 0]
                        stage.addChild(g)
                    }
                }
                runStart = i
            }
        }
        // centre dashes
        var dash = EnvironmentBuilder.glow(.white, opacity: 0.35)
        dash.faceCulling = .none
        for i in stride(from: 0, to: n - 4, by: 8) {
            if let m = ribbon(from: i, to: i + 3, offset: 0, width: 0.008, y: 0.002) { stage.addChild(ModelEntity(mesh: m, materials: [dash])) }
        }
        // start / finish line
        let f = frame(at: 0)
        let line = ModelEntity(mesh: .generateBox(size: [w, 0.004, 0.03]), materials: [EnvironmentBuilder.glow(.white, opacity: 0.9)])
        line.position = f.p + [0, 0.004, 0]
        line.orientation = simd_quatf(from: [0, 0, -1], to: f.tangent)
        stage.addChild(line)
        for side: Float in [-1, 1] {
            let post = RhythmStepGame.makeLantern(scale: 0.5)
            post.position = f.p + f.side * side * (w / 2 + 0.06) + [0, 0.12, 0]
            stage.addChild(post)
        }
    }

    private func placeOrbs() {
        var last: Float = -1
        var s: Float = 0.4
        while s < length - 0.2 {
            let i = index(at: s)
            if comfort[i] >= 0.55 && s - last > 0.42 {
                let f = frame(at: s)
                let e = Entity()
                e.addChild(ModelEntity(mesh: .generateSphere(radius: 0.022), materials: [EnvironmentBuilder.glow(UIColor(red: 0.9, green: 0.97, blue: 1, alpha: 1))]))
                e.addChild(ModelEntity(mesh: .generateSphere(radius: 0.045), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.25)]))
                e.position = f.p + [0, 0.07, 0]
                stage.addChild(e)
                orbs.append(Orb(e: e, s: s))
                last = s
            }
            s += 0.05
        }
    }

    private func loadCar(into holder: Entity, opacity: Float) async {
        let body: Entity
        if let model = try? await Entity(named: "RaceCar", in: .main) {
            // "3D Cartoon Toy Race Car with Vibrant Colors" by Skill Artist (Sketchfab, CC BY 4.0), credited in Settings
            // The file is posed at a showroom angle; this rotation (from its principal axes) sets it flat,
            // nose along −Z, spoiler at the back.
            let h = Entity(); h.addChild(model)
            model.orientation = simd_quatf(ix: -0.05009, iy: 0.90594, iz: 0.07983, r: 0.41278) * model.orientation
            let b = model.visualBounds(relativeTo: h)
            let sc = 0.24 / max(b.extents.z, 0.001)
            h.scale = [sc, sc, sc]
            model.position -= [b.center.x, b.min.y, b.center.z]
            body = h
        } else {
            body = Self.makeCar()
        }
        holder.addChild(body)
        // headlight glow so it reads as yours on the dark road
        let glow = ModelEntity(mesh: .generateSphere(radius: 0.08), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.12)])
        glow.position = [0, 0.03, 0]
        holder.addChild(glow)
        if opacity < 1 { holder.components.set(OpacityComponent(opacity: opacity)) }
    }

    static func makeCar() -> Entity {
        let e = Entity()
        var paint = PhysicallyBasedMaterial()
        paint.baseColor = .init(tint: UIColor(red: 0.3, green: 0.85, blue: 0.85, alpha: 1))
        paint.roughness = .init(floatLiteral: 0.35)
        let body = ModelEntity(mesh: .generateBox(size: [0.11, 0.04, 0.22], cornerRadius: 0.015), materials: [paint])
        body.position.y = 0.04
        e.addChild(body)
        let cab = ModelEntity(mesh: .generateBox(size: [0.08, 0.035, 0.08], cornerRadius: 0.012), materials: [SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), isMetallic: false)])
        cab.position = [0, 0.075, 0.02]
        e.addChild(cab)
        for x: Float in [-0.06, 0.06] { for z: Float in [-0.07, 0.07] {
            let w = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.022), materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1), isMetallic: false)])
            w.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            w.position = [x, 0.022, z]
            e.addChild(w)
        } }
        return e
    }

    // MARK: Update
    func update(dt: Float, time: Double, tracker: MotionTracker) {
        guard dt > 0, !finished else { return }
        t += dt
        pedal.update(dt: dt, tracker: tracker)
        if let c = pedal.connectionChanged {
            feedback = c ? "iPhone connected. Point your toes down slowly to drive" : "iPhone disconnected. Open Motial Pedal to keep driving"
            SoundManager.shared.play(c ? "sfx_chime" : "sfx_tap", volume: 0.4)
        }
        anatomy.update(value: pedal.value, velocity: pedal.velocity, dt: dt)
        audio.update(speed01: speed / Self.maxSpeed)
        smoothSum += pedal.smooth * dt; smoothN += dt

        // pedal → speed: smooth pressing gives full power; releasing coasts and gently slows
        let target = pedal.value * (0.4 + 0.6 * pedal.smooth) * Self.maxSpeed
        if target > speed { speed += (target - speed) * min(1, dt * 1.4) }
        else { speed -= speed * min(1, dt * 0.35) }

        let i = index(at: s)
        let c = comfort[i]
        let corner = c < Self.cornerSpeed

        // look ahead: warn before a corner if too fast
        let ahead = comfort[index(at: s + 0.7)]
        if !warned && ahead < Self.cornerSpeed && speed > ahead + 0.06 {
            warned = true
            feedback = config.seated ? "Corner ahead: bring your toes up slowly" : "Corner ahead: lower your heels slowly"
            SoundManager.shared.play("sfx_tick", volume: 0.4)
        }
        if corner && !inCorner { inCorner = true; cornerSlid = false; cornersEntered += 1 }
        if !corner && inCorner {
            inCorner = false
            warned = false
            if !cornerSlid {
                cleanCorners += 1
                score += 2
                feedback = ["Clean corner", "Smooth line", "Perfect control", "Lovely corner"][cleanCorners % 4]
                SoundManager.shared.play("sfx_chime", volume: 0.5)
                sparkles.burst(at: car.position(relativeTo: nil) + [0, 0.08, 0], color: Palette.gold, count: 16, speed: 0.5)
            }
        }
        let over = speed - c
        if over > 0.04 {
            slide = min(1, slide + dt * over * 7)
            speed -= over * dt * 2.5
            if !cornerSlid {
                cornerSlid = true
                slides += 1
                feedback = "A little fast. Ease off before the gold corners"
                SoundManager.shared.play("sfx_tyre_slide", volume: 0.45)
            }
        } else {
            slide = max(0, slide - dt * 0.8)
        }

        // jerky pedal: wheel-spin puffs, no extra grip
        rippleCooldown -= dt
        if pedal.jerkSpike && rippleCooldown <= 0 {
            rippleCooldown = 1
            spawnRipple(at: car.position)
            feedback = "Smooth pedal, more grip"
        }

        s += speed * dt
        lapTime += dt
        traceTimer += dt
        if traceTimer >= 0.1 { traceTimer = 0; trace.append(s) }
        placeCar()

        // orbs on the straights: collected when you pass with some pace
        for k in orbs.indices {
            if orbs[k].taken {
                if orbs[k].fly < 3 {
                    orbs[k].fly += dt
                    orbs[k].e.position.y += dt * 0.6
                    orbs[k].e.components.set(OpacityComponent(opacity: max(0, 1 - orbs[k].fly / 3)))
                }
                continue
            }
            orbs[k].e.position.y = 0.07 + sin(t * 2 + orbs[k].s * 3) * 0.01
            let lapS = s - Float(lap - 1) * length
            if lapS >= orbs[k].s && lapS - orbs[k].s < 0.3 {
                if speed > 0.22 {
                    orbs[k].taken = true
                    orbsCollected += 1
                    score += 1
                    SoundManager.shared.play("sfx_shimmer", volume: 0.4)
                    sparkles.burst(at: orbs[k].e.position(relativeTo: nil), color: Palette.teal, count: 8, speed: 0.4, size: 0.008)
                }
            }
        }

        // ghost of the best lap
        if !bestTrace.isEmpty {
            ghost.isEnabled = true
            ghostClock += dt
            let gi = min(bestTrace.count - 1, Int(ghostClock / 0.1))
            let gs = bestTrace[gi] - bestTrace[0]
            let f = frame(at: gs)
            ghost.position = f.p + f.side * 0.07
            ghost.orientation = simd_quatf(from: [0, 0, -1], to: f.tangent)
        }

        // lap complete
        if s >= Float(lap) * length {
            let time = lapTime
            let isBest = bestLap == nil || time < bestLap!
            if isBest {
                bestLap = time
                bestTrace = trace
                UserDefaults.standard.set(time, forKey: bestKey)
            }
            feedback = isBest && lap > 1 ? "New best lap: \(String(format: "%.1f", time)) s"
                                         : "Lap \(lap): \(String(format: "%.1f", time)) s"
            SoundManager.shared.play(isBest ? "sfx_lap_fanfare" : "sfx_beat", volume: 0.6)
            sparkles.burst(at: car.position(relativeTo: nil) + [0, 0.1, 0], color: Palette.gold, count: 24, speed: 0.7)
            lap += 1
            lapTime = 0
            trace = [s]
            ghostClock = 0
            for k in orbs.indices {                       // orbs return for the next lap
                orbs[k].taken = false; orbs[k].fly = 0
                orbs[k].e.position.y = 0.07
                orbs[k].e.components.set(OpacityComponent(opacity: 1))
            }
            ShinLink.shared.sendStatus("Dawn Drive · lap \(min(lap, Self.laps)) of \(Self.laps) · \(orbsCollected) orbs")
        }
        if lap > Self.laps {
            doneTimer += dt
            speed *= 0.9
            if doneTimer > 2 {
                finished = true
                SoundManager.shared.play("sfx_levelup", volume: 0.7)
                let medal = cleanCorners >= Self.laps * 3 ? "Gold" : cleanCorners >= Self.laps * 2 ? "Silver" : "Bronze"
                feedback = "\(medal) finish. \(cleanCorners) clean corners and \(orbsCollected) orbs"
                ShinLink.shared.sendStatus("\(medal) finish · \(orbsCollected) orbs")
            }
        }

        updateRipples(dt: dt)
        sparkles.update(dt: dt)
    }

    private func placeCar() {
        let f = frame(at: s)
        let i = index(at: s)
        let outward = -turn[i] * slide * 0.09
        car.position = f.p + f.side * outward
        let drift = simd_quatf(angle: turn[i] * slide * 0.35, axis: [0, 1, 0])
        car.orientation = drift * simd_quatf(from: [0, 0, -1], to: f.tangent)
    }

    private func spawnRipple(at p: SIMD3<Float>) {
        guard let ring = EnvironmentBuilder.annulus(inner: 0.06, outer: 0.07) else { return }
        let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(.white, opacity: 0.5)])
        r.position = [p.x, 0.016, p.z]
        stage.addChild(r)
        ripples.append(Ripple(e: r, t: 0))
        SoundManager.shared.play("sfx_drop", volume: 0.2)
    }

    private func updateRipples(dt: Float) {
        for k in ripples.indices.reversed() {
            ripples[k].t += dt
            let u = ripples[k].t / 1.2
            ripples[k].e.scale = [1 + 2.5 * u, 1, 1 + 2.5 * u]
            ripples[k].e.components.set(OpacityComponent(opacity: max(0, 1 - u)))
            if u >= 1 { ripples[k].e.removeFromParent(); ripples.remove(at: k) }
        }
    }

    /// Lumi flies just ahead of the car along the track.
    var guidePoint: SIMD3<Float>? {
        guard !pts.isEmpty else { return nil }
        return stage.convert(position: frame(at: s + 0.8).p + [0, 0.3, 0], to: nil)
    }

    func handleTap(_ entity: Entity) -> Bool { false }

    func stop() {
        finished = true
        audio.stop()
        sparkles.clear()
        root.removeFromParent()
    }
}
