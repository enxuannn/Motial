import RealityKit
import UIKit
import simd

/// Lantern Glide: standing heel raises row a little lantern boat across the lake.
/// Rising onto the toes (pointing the toes down) pushes the boat forward; lowering the heels slowly lets it glide on
/// and gently slow. A smooth, steady pace lights the lanterns along the route and they float up into the sky;
/// jerky or bouncing movement only makes ripples. There is no timer, no opponent and no speed score:
/// control is the goal (slow, controlled heel raises with a 3-second lowering, JOSPT 2021 calf strengthening).
/// Seated version: an iPhone strapped to the top of the foot runs the "Motial Pedal"
/// companion app and streams how far the toes point down (see ShinLink); the same smoothness rules apply.
@MainActor
final class LanternGlideGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var stats: [GameStat] {
        [GameStat(value: "\(score)/\(gates.count)", label: "Lanterns lit", progress: Double(score) / Double(max(1, gates.count))),
         GameStat(value: "\(Int(smooth * 100))%", label: "Smoothness", progress: Double(smooth))]
    }
    var pedalLevel: Float? { anatomy.level }
    var summary: GameSummary? {
        GameSummary(orbs: 0, cleared: score, total: gates.filter(\.passed).count, obstacleName: "lanterns",
                    bestLap: nil, smoothness: Double(smooth), completed: gates.allSatisfy(\.passed))
    }
    var learnTip: String? { anatomy.tip }
    var status: String { "Lanterns \(score) of \(gates.count) · smooth \(Int(smooth * 100))%" }

    private let config: GameConfig
    private let stage = Entity()          // local frame: -Z is straight ahead of the person
    private let route = Entity()          // slides toward the person as the boat glides
    private let boat = Entity()
    private let sparkles = Sparkles()
    private let anatomy = LiveAnkle()

    private struct Gate {
        let lantern: Entity
        let z: Float
        var passed = false
        var lit = false
        var age: Float = 0
        var sky = SIMD3<Float>(0, 0, 0)
    }
    private var gates: [Gate] = []
    private struct Ripple { let e: ModelEntity; var t: Float; let life: Float }
    private var ripples: [Ripple] = []
    private var motes: [Entity] = []

    // movement reading
    private var baseline: Float?
    private var lastY: Float?
    private var vy: Float = 0
    private var lastVy: Float = 0
    private var jerk: Float = 0
    private(set) var smooth: Float = 0.8
    private var rises = HeadRepCounter(direction: .up)
    private(set) var heelRaises = 0
    private var demo = false
    private var phoneWasConnected = false

    // boat
    private var speed: Float = 0
    private var distance: Float = 0
    private var rock: Float = 0
    private var rippleCooldown: Float = 0
    private var wakeTimer: Float = 0
    private var idle: Float = 0
    private var t: Float = 0
    private var doneTimer: Float = 0

    static let boatZ: Float = -2.0
    static let spacing: Float = 2.6
    static let maxSpeed: Float = 0.75     // m/s at full, smooth rise

    init(config: GameConfig) { self.config = config }

    // MARK: Setup
    func start(tracker: MotionTracker) {
        stage.position = [tracker.centre.x, 0, tracker.centre.z]
        stage.orientation = yawToward(tracker.headForward)
        root.addChild(stage)
        root.addChild(sparkles.root)
        stage.addChild(route)
        if config.seated {
            ShinLink.shared.start()        // seated: the iPhone on the foot / shin steers the boat
            demo = !ShinLink.shared.connected
            phoneWasConnected = !demo
        } else {
            demo = !tracker.running        // simulator or no tracking: a calm demo pace so the game can be shown
        }
        rises.threshold = 0.025

        // the glide lane: a soft band of light across the water
        let lane = ModelEntity(mesh: .generatePlane(width: 1.4, depth: 16), materials: [EnvironmentBuilder.glow(Palette.water, opacity: 0.18)])
        lane.position = [0, 0.01, Self.boatZ - 6.5]
        stage.addChild(lane)
        for side: Float in [-0.72, 0.72] {
            let edge = ModelEntity(mesh: .generatePlane(width: 0.015, depth: 16), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.35)])
            edge.position = [side, 0.012, Self.boatZ - 6.5]
            stage.addChild(edge)
        }
        // drifting light motes on the water show the glide
        for i in 0..<28 {
            let m = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [EnvironmentBuilder.glow(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1), opacity: 0.7)])
            m.position = [Float.random(in: -0.65...0.65), 0.015, -Float(i) * 0.5 - 0.5]
            stage.addChild(m)
            motes.append(m)
        }

        // "Your ankle, live" beside the lake, turned toward the person
        let ap = SIMD3<Float>(-1.15, config.seated ? 1.0 : 1.25, -1.5)   // left, clear of the session panel
        anatomy.root.position = ap
        stage.addChild(anatomy.root)
        anatomy.root.look(at: [2 * ap.x, ap.y, 2 * ap.z], from: ap, relativeTo: stage)
        Task { @MainActor in await self.anatomy.load() }

        // the boat: a bundled "Boat.usdz" is used when present (e.g. a CC0 / CC BY model), else the built-in one
        boat.position = [0, 0.03, Self.boatZ]
        stage.addChild(boat)
        Task { @MainActor in
            if let model = try? await Entity(named: "Boat", in: .main) {
                // "Stylized Low Poly Rowboat with Paddles" by Muyaya Concept (Sketchfab, CC BY 4.0), credited in Settings
                let holder = Entity()
                holder.addChild(model)
                var b = model.visualBounds(relativeTo: holder)
                if b.extents.x > b.extents.z {                      // long axis along Z (toward / away from the person)
                    model.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    b = model.visualBounds(relativeTo: holder)
                }
                let len = max(b.extents.x, b.extents.z)
                let s: Float = len > 0 ? 1.0 / len : 1
                holder.scale = [s, s, s]
                model.position -= [b.center.x, b.min.y, b.center.z]   // centred, keel on the water
                self.boat.addChild(holder)
                // our own touch: a paper lantern on a pole at the bow
                let pole = ModelEntity(mesh: .generateCylinder(height: 0.44, radius: 0.005),
                                       materials: [SimpleMaterial(color: UIColor(red: 0.35, green: 0.23, blue: 0.14, alpha: 1), isMetallic: false)])
                pole.position = [0, 0.3, -0.36]
                pole.orientation = simd_quatf(angle: -0.25, axis: [1, 0, 0])
                self.boat.addChild(pole)
                let lamp = RhythmStepGame.makeLantern(scale: 0.5)
                lamp.position = [0, 0.47, -0.43]
                self.boat.addChild(lamp)
                let halo = ModelEntity(mesh: .generateSphere(radius: 0.11),
                                       materials: [EnvironmentBuilder.glow(RhythmStepGame.lanternWarm, opacity: 0.18)])
                halo.position = lamp.position
                self.boat.addChild(halo)
            } else {
                self.boat.addChild(Self.makeBoat())
            }
        }
        if let glowRing = EnvironmentBuilder.annulus(inner: 0.0, outer: 0.55) {
            let g = ModelEntity(mesh: glowRing, materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.12)])
            g.position.y = -0.018
            boat.addChild(g)
        }

        // lanterns along the route, alternating sides
        let n = max(4, config.count)
        for i in 0..<n {
            let z = Self.boatZ - Self.spacing * Float(i + 1)
            let l = Entity()
            let lamp = RhythmStepGame.makeLantern(scale: 1.1)
            l.addChild(lamp)
            if let ring = EnvironmentBuilder.annulus(inner: 0.08, outer: 0.12) {
                let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.35)])
                r.position.y = -0.43
                l.addChild(r)
            }
            l.position = [i % 2 == 0 ? -0.5 : 0.5, 0.45, z]
            l.components.set(OpacityComponent(opacity: 0.32))
            route.addChild(l)
            gates.append(Gate(lantern: l, z: z))
        }
        if config.seated {
            feedback = demo ? "Open Motial Pedal on your iPhone to steer with your ankle"
                            : "Point your toes down slowly to set off"
        } else {
            feedback = demo ? "Demo pace: watch how a slow rise and slow lower glides the boat"
                            : "Rise slowly onto your toes to set off"
        }
        ShinLink.shared.sendStatus("Lanterns 0 of \(gates.count)")
    }

    // MARK: Update
    func update(dt: Float, time: Double, tracker: MotionTracker) {
        guard dt > 0, !finished else { return }
        t += dt

        // Seated: follow the phone; fall back to the demo pace while it is not connected
        if config.seated {
            let link = ShinLink.shared
            demo = !link.connected
            if link.connected != phoneWasConnected {
                phoneWasConnected = link.connected
                lastY = nil; vy = 0; lastVy = 0; jerk = 0
                feedback = link.connected ? "iPhone connected. Point your toes down slowly to glide"
                                          : "iPhone disconnected. Open Motial Pedal to keep steering"
                SoundManager.shared.play(link.connected ? "sfx_chime" : "sfx_tap", volume: 0.4)
            }
        }

        // 1. Read the heel raise from head height (≈ 4–7 cm rise), or the ankle from the phone (seated)
        let y: Float
        if config.seated && !demo {
            y = 1.6 + 0.05 * ShinLink.shared.value          // same scale as a heel raise, so one pipeline judges both
        } else if demo {
            let ph = fmod(t, 5.0)                                  // up 1.2 s, hold 0.6 s, lower 2.6 s, rest
            let s: Float = ph < 1.2 ? ph / 1.2 : (ph < 1.8 ? 1 : max(0, 1 - (ph - 1.8) / 2.6))
            y = 1.6 + 0.05 * s * s * (3 - 2 * s)
        } else {
            y = tracker.head.y
        }
        var b = config.seated && !demo ? 1.6 : (baseline ?? y)   // seated: the phone is already calibrated
        let liftNow = y - b
        if liftNow < 0 { b += liftNow * min(1, dt * 2) }            // settled lower than before: follow quickly
        else if liftNow < 0.012 { b += liftNow * min(1, dt * 0.5) } // slow posture drift while heels are down
        baseline = b
        let lift = y - b
        anatomy.update(value: clamp01((lift - 0.008) / 0.042), velocity: vy / 0.042, dt: dt)

        let rawV = lastY.map { (y - $0) / dt } ?? 0
        lastY = y
        vy += (rawV - vy) * min(1, dt * 10)
        let acc = (vy - lastVy) / dt
        lastVy = vy
        jerk += (abs(acc) - jerk) * min(1, dt * 3)
        let horiz = (demo || config.seated) ? 0 : simd_length(SIMD2<Float>(tracker.headVelocity.x, tracker.headVelocity.z))

        // 2. Smoothness: low jerk, no bouncing, little side-to-side sway
        let calm = clamp01(1 - (jerk - 0.35) / 1.4)
        let still = clamp01(1 - (horiz - 0.12) / 0.25)
        let unhurried: Float = abs(vy) > 0.3 ? 0.3 : 1
        smooth += (calm * still * unhurried - smooth) * min(1, dt * 0.8)

        rises.add(y)
        if rises.count > heelRaises {
            heelRaises = rises.count
            SoundManager.shared.play("sfx_shimmer", volume: 0.35)
            if score == 0 && heelRaises == 1 {
                feedback = config.seated ? "Lovely. Now bring your toes back up slowly, the boat keeps gliding"
                                         : "Lovely. Now lower slowly, the boat keeps gliding"
            }
        }

        // 3. Boat: toes down (rising) pushes forward, heels down lets it glide and slowly ease off
        let elevated = clamp01((lift - 0.012) / 0.035)
        let target = elevated * (0.35 + 0.65 * smooth) * Self.maxSpeed
        if target > speed { speed += (target - speed) * min(1, dt * 1.6) }
        else { speed -= speed * min(1, dt * 0.22) }
        distance += speed * dt
        route.position.z = distance

        idle = speed < 0.04 ? idle + dt : 0
        if idle > 6, !demo {
            idle = 0
            feedback = config.seated ? "Whenever you're ready: point your toes down slowly"
                                     : "Whenever you're ready: rise slowly onto your toes"
        }
        ShinLink.shared.sendStatus("Lanterns \(score) of \(gates.count)")

        // jerky movement: ripples instead of lanterns
        rippleCooldown -= dt
        if !demo, rippleCooldown <= 0, abs(acc) > 2.2 || abs(vy) > 0.32 || horiz > 0.35 {
            rippleCooldown = 1.0
            rock = 1
            spawnRipple(at: boat.position + [0, -0.02, 0], color: Palette.teal)
            SoundManager.shared.play("sfx_drop", volume: 0.25)
            feedback = "Easy… slow and smooth lights the lanterns"
        }
        rock = max(0, rock - dt * 1.2)
        boat.position.y = 0.03 + sin(t * 1.6) * 0.008 + rock * 0.015 * sin(t * 11)
        boat.orientation = simd_quatf(angle: rock * 0.12 * sin(t * 9) + sin(t * 1.1) * 0.02, axis: [0, 0, 1])
            * simd_quatf(angle: -speed * 0.05, axis: [1, 0, 0])

        // wake sparkles and drifting water motes
        wakeTimer += dt
        if speed > 0.15 && wakeTimer > 0.25 {
            wakeTimer = 0
            let p = stage.convert(position: boat.position + [Float.random(in: -0.12...0.12), 0.01, 0.5], to: nil)
            sparkles.burst(at: p, color: UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1), count: 3, speed: 0.15, size: 0.007)
        }
        for m in motes {
            m.position.z += speed * dt
            if m.position.z > -0.3 { m.position.z -= 14; m.position.x = Float.random(in: -0.65...0.65) }
        }

        // 4. Lanterns: passed smoothly → lit and released into the sky; passed jerkily → stays dark, drifts by
        for i in gates.indices {
            let localZ = gates[i].z + distance
            if !gates[i].passed && localZ > Self.boatZ {
                gates[i].passed = true
                if smooth >= 0.55 || demo { light(i) }
                else {
                    feedback = "That one stayed dark. Slower and smoother for the next"
                    spawnRipple(at: gates[i].lantern.position(relativeTo: stage) + [0, -0.43, 0], color: Palette.water)
                }
            }
            guard gates[i].passed else { continue }
            gates[i].age += dt
            let l = gates[i].lantern
            if gates[i].lit {
                // float up to its place in the sky ahead, where the lit lanterns gather as visible progress
                let k = min(1, dt * 0.35)
                l.position += (gates[i].sky - l.position) * k
                l.position.y += sin(t * 0.8 + Float(i)) * 0.0008
            } else {
                let o = max(0, 0.32 - gates[i].age * 0.12)
                l.components.set(OpacityComponent(opacity: o))
                if o == 0 { l.isEnabled = false }
            }
        }

        updateRipples(dt: dt)
        sparkles.update(dt: dt)

        if gates.allSatisfy({ $0.passed }) {
            doneTimer += dt
            if doneTimer > 2.5 {
                finished = true
                SoundManager.shared.play("sfx_levelup", volume: 0.7)
                feedback = score == gates.count ? "Every lantern is glowing. Beautiful control"
                                                 : "\(score) lanterns lit. Lovely work"
                ShinLink.shared.sendStatus(score == gates.count ? "Every lantern is glowing" : "\(score) lanterns lit")
            }
        }
    }

    private func light(_ i: Int) {
        gates[i].lit = true
        score += 1
        let l = gates[i].lantern
        let world = l.transformMatrix(relativeTo: stage)
        l.removeFromParent()
        stage.addChild(l)
        l.transform = Transform(matrix: world)
        l.components.set(OpacityComponent(opacity: 1))
        gates[i].sky = [Float.random(in: -2.6...2.6), Float.random(in: 2.6...4.2), Self.boatZ - Float.random(in: 5...9)]
        let p = l.position(relativeTo: nil)
        sparkles.burst(at: p, color: Palette.gold, count: 18, speed: 0.6)
        SoundManager.shared.play("sfx_chime", volume: 0.55)
        let praise = ["Lovely and smooth", "A lantern rises", "Steady glide", "Beautiful control", "Gentle and calm"]
        feedback = score == 1 ? "Your first lantern is in the sky" : praise[score % praise.count]
    }

    private func spawnRipple(at p: SIMD3<Float>, color: UIColor) {
        guard let ring = EnvironmentBuilder.annulus(inner: 0.12, outer: 0.135) else { return }
        for k in 0..<2 {
            let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(color, opacity: 0.6)])
            r.position = [p.x, 0.014 + Float(k) * 0.002, p.z]
            stage.addChild(r)
            ripples.append(Ripple(e: r, t: -Float(k) * 0.3, life: 2.2))
        }
    }

    private func updateRipples(dt: Float) {
        for i in ripples.indices.reversed() {
            ripples[i].t += dt
            let u = max(0, ripples[i].t / ripples[i].life)
            let s = 1 + u * 3
            ripples[i].e.scale = [s, 1, s]
            ripples[i].e.components.set(OpacityComponent(opacity: max(0, 1 - u)))
            if u >= 1 { ripples[i].e.removeFromParent(); ripples.remove(at: i) }
        }
    }

    private func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }

    /// Lumi flies ahead along the route, over the next lantern.
    var guidePoint: SIMD3<Float>? {
        guard let g = gates.first(where: { !$0.passed }) else { return nil }
        return g.lantern.position(relativeTo: nil) + [0, 0.35, 0]
    }

    func handleTap(_ entity: Entity) -> Bool { false }

    func stop() {
        finished = true
        sparkles.clear()
        ripples.forEach { $0.e.removeFromParent() }
        ripples.removeAll()
        root.removeFromParent()
    }

    // MARK: Built-in boat (procedural, no licence needed)
    /// A small wooden rowing boat lofted from 19 cross-sections, with a seat and a paper lantern on a pole.
    static func makeBoat() -> Entity {
        let e = Entity()
        let L: Float = 0.9, W: Float = 0.34, D: Float = 0.13
        let stations = 18, ring = 10
        var pos: [SIMD3<Float>] = []
        for i in 0...stations {
            let u = Float(i) / Float(stations)                         // 0 = stern (near the person), 1 = bow
            let z = (0.5 - u) * L
            let shape = pow(max(0, sin(Float.pi * (0.1 + 0.9 * u))), 0.55)
            let sheer = D * (1 + 0.7 * pow(max(0, u - 0.55) / 0.45, 2) + 0.15 * pow(max(0, 0.25 - u) / 0.25, 2))
            let depth = sheer * (0.25 + 0.75 * pow(shape, 0.4))
            for j in 0...ring {
                let a = Float.pi * Float(j) / Float(ring)
                pos.append([-cos(a) * W / 2 * shape, sheer - sin(a) * depth, z])
            }
        }
        var idx: [UInt32] = []
        let rw = UInt32(ring + 1)
        for i in 0..<UInt32(stations) {
            for j in 0..<UInt32(ring) {
                let a = i * rw + j, b = (i + 1) * rw + j
                idx += [a, b, b + 1, a, b + 1, a + 1]
            }
        }
        // transom (flat stern board)
        let centre = UInt32(pos.count)
        pos.append([0, D * 0.75, L / 2])
        for j in 0..<UInt32(ring) { idx += [centre, j + 1, j] }
        // smooth normals
        var nrm = [SIMD3<Float>](repeating: .zero, count: pos.count)
        for k in stride(from: 0, to: idx.count, by: 3) {
            let (a, b, c) = (Int(idx[k]), Int(idx[k + 1]), Int(idx[k + 2]))
            let n = simd_cross(pos[b] - pos[a], pos[c] - pos[a])
            nrm[a] += n; nrm[b] += n; nrm[c] += n
        }
        nrm = nrm.map { simd_length($0) > 0 ? simd_normalize($0) : [0, 1, 0] }
        var md = MeshDescriptor(name: "hull")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(nrm)
        md.primitives = .triangles(idx)
        var wood = PhysicallyBasedMaterial()
        wood.baseColor = .init(tint: UIColor(red: 0.58, green: 0.38, blue: 0.23, alpha: 1))
        wood.roughness = .init(floatLiteral: 0.75)
        wood.faceCulling = .none
        if let mesh = try? MeshResource.generate(from: [md]) {
            e.addChild(ModelEntity(mesh: mesh, materials: [wood]))
        }
        var light = PhysicallyBasedMaterial()
        light.baseColor = .init(tint: UIColor(red: 0.80, green: 0.62, blue: 0.42, alpha: 1))
        light.roughness = .init(floatLiteral: 0.7)
        // gunwale trim
        for s: Float in [-1, 1] {
            let rail = ModelEntity(mesh: .generateBox(size: [0.012, 0.012, L * 0.78], cornerRadius: 0.004), materials: [light])
            rail.position = [s * W * 0.47, D * 1.02, 0.03]
            e.addChild(rail)
        }
        // seat
        let seat = ModelEntity(mesh: .generateBox(size: [W * 0.92, 0.014, 0.08], cornerRadius: 0.004), materials: [light])
        seat.position = [0, D * 0.78, 0.06]
        e.addChild(seat)
        // lantern pole at the bow, leaning forward, with a glowing paper lantern
        let pole = ModelEntity(mesh: .generateCylinder(height: 0.42, radius: 0.005), materials: [wood])
        pole.position = [0, D + 0.19, -L * 0.36]
        pole.orientation = simd_quatf(angle: -0.25, axis: [1, 0, 0])
        e.addChild(pole)
        let lamp = RhythmStepGame.makeLantern(scale: 0.5)
        lamp.position = [0, D + 0.36, -L * 0.36 - 0.1]
        e.addChild(lamp)
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [EnvironmentBuilder.glow(RhythmStepGame.lanternWarm, opacity: 0.18)])
        halo.position = lamp.position
        e.addChild(halo)
        return e
    }
}
