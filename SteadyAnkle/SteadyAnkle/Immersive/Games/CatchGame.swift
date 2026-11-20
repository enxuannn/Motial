import RealityKit
import UIKit
import simd

/// One-Leg Catch, baseball style. A glowing pitcher's spot throws real baseballs toward the person, who wears
/// a glove on the tracked hand. Clinical design (MGH ankle protocol phase III "ball toss with decreased base of
/// support"; reactive balance as used in clinic ball-toss drills):
/// - set 1 starts with a few warm-up throws on BOTH feet, then the person lifts the other foot and the rest
///   are caught on ONE leg; later sets are one-leg from the start
/// - level 1 throws come straight on, level 2 from three directions, level 3 from five directions and heights,
///   so the person must react rather than anticipate
/// Catch with a hand (hand tracking) or, if hand tracking is off, look at the ball and pinch.
@MainActor
final class CatchGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var status: String {
        let phase = announcedOneLeg ? "One leg" : "Warm-up on both feet"
        return "\(phase) · Caught \(score) of \(thrown)"
    }

    private struct Ball { let e: Entity; let from: SIMD3<Float>; let to: SIMD3<Float>; let t0: Double; let flight: Double; var done: Bool }
    private let config: GameConfig
    private var balls: [Ball] = []
    private var thrown = 0
    private var nextThrow: Double = 0
    private var portal = Entity()
    private let sparkles = Sparkles()
    private var centre = SIMD3<Float>(0, 0, 0)
    private var forward = SIMD3<Float>(0, 0, -1)
    private var origin = SIMD3<Float>(0, 1.3, -4)
    private var portalTarget = SIMD3<Float>(0, 1.3, -4)
    private var sway = SwayMeter()
    private var combo = 0
    private var handMarkers: [ModelEntity] = []
    private var ballTemplate: Entity?
    private var glove: Entity?
    private var gloveOnRight = false
    private var announcedOneLeg = false
    private var spotForThrow = -1

    init(config: GameConfig) { self.config = config }

    private var level: Int { max(1, min(3, config.level)) }
    private var interval: Double { [3.4, 2.8, 2.3][level - 1] + (config.fallRisk ? 0.6 : 0) }
    private var flight: Double { [1.9, 1.6, 1.35][level - 1] + (config.fallRisk ? 0.2 : 0) }
    private var spread: Float { [0.20, 0.34, 0.48][level - 1] * (config.fallRisk ? 0.7 : 1) }
    /// Throw directions in degrees, relative to straight ahead.
    private var angles: [Float] { [[0], [-25, 0, 25], [-45, -22, 0, 22, 45]][level - 1] }
    /// Warm-up throws on both feet before going single-leg (first set only; more for higher fall risk).
    private var warmups: Int { config.setNumber > 1 ? 0 : (config.fallRisk ? 3 : [3, 2, 1][level - 1]) }

    func start(tracker: MotionTracker) {
        root.addChild(sparkles.root)
        forward = simd_normalize(SIMD3<Float>(tracker.headForward.x, 0, tracker.headForward.z))
        centre = tracker.centre
        origin = spot(angle: 0, height: 1.35)
        portalTarget = origin
        portal.position = origin
        portal.orientation = yawToward(-forward)
        if let ring = EnvironmentBuilder.annulus(inner: 0.32, outer: 0.38) {
            let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.9)])
            r.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            portal.addChild(r)
        }
        if let disc = EnvironmentBuilder.annulus(inner: 0, outer: 0.32) {
            let d = ModelEntity(mesh: disc, materials: [EnvironmentBuilder.glow(Palette.violet, opacity: 0.35)])
            d.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            portal.addChild(d)
        }
        root.addChild(portal)
        for _ in 0..<2 {
            let m = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.25)])
            m.isEnabled = false
            root.addChild(m); handMarkers.append(m)
        }
        Task { @MainActor in
            let loadedBall = try? await Entity(named: "Baseball", in: .main)
            self.ballTemplate = loadedBall
            let loadedGlove = try? await Entity(named: "Glove", in: .main)
            if let g = loadedGlove {
                g.isEnabled = false
                self.root.addChild(g)
                self.glove = g
            }
        }
        nextThrow = 2.0
        sway.reset()
        if warmups > 0 {
            feedback = "Warm-up: catch on both feet first"
            SoundManager.shared.say("Warm up first. Keep both feet down and catch the ball.")
        } else {
            announcedOneLeg = true
            feedback = "Balance on your \(config.injured.short.lowercased()) leg and catch"
        }
    }

    /// A pitcher's spot 4 m away at a given angle from straight ahead.
    private func spot(angle deg: Float, height: Float) -> SIMD3<Float> {
        let a = deg * .pi / 180
        let rot = simd_quatf(angle: -a, axis: [0, 1, 0])
        let dir = rot.act(forward)
        return centre + dir * 4.0 + [0, height, 0]
    }

    private func throwBall(time: Double, tracker: MotionTracker) {
        let side = Float.random(in: -1...1)
        let right = simd_normalize(simd_cross(tracker.headForward, [0, 1, 0]))
        let target = SIMD3<Float>(tracker.head.x, tracker.head.y - Float.random(in: 0.25...0.5), tracker.head.z)
            + tracker.headForward * 0.45 + right * side * spread
        let e: Entity
        if let t = ballTemplate {
            e = t.clone(recursive: true)
        } else {
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: .white)
            mat.roughness = .init(floatLiteral: 0.5)
            let m = ModelEntity(mesh: .generateSphere(radius: 0.037), materials: [mat])
            m.addChild(ModelEntity(mesh: .generateBox(size: [0.076, 0.005, 0.005]), materials: [EnvironmentBuilder.glow(.red)]))
            e = m
        }
        // a soft glow makes the ball easy to see against any scene
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [EnvironmentBuilder.glow(UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), opacity: 0.18)])
        e.addChild(halo)
        e.components.set(InputTargetComponent())
        e.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.09)]))
        e.components.set(HoverEffectComponent())
        e.name = "Ball"
        e.position = origin
        root.addChild(e)
        balls.append(Ball(e: e, from: origin, to: target, t0: time, flight: flight, done: false))
        thrown += 1
        SoundManager.shared.playSpatial("sfx_pitch", on: portal)
    }

    /// Move the pitcher's spot before the next throw, so the direction is a surprise but still visible.
    private func choosePitcherSpot() {
        let a = angles.randomElement() ?? 0
        let h: Float = level == 3 ? Float.random(in: 1.15...1.55) : 1.35
        portalTarget = spot(angle: a, height: h)
    }

    private func updateGlove(_ left: SIMD3<Float>?, _ right: SIMD3<Float>?) {
        guard let g = glove else { return }
        // Glove on the left hand (most people catch with the left); use the right hand if only that one is tracked.
        let hand = left ?? right
        guard let h = hand else { g.isEnabled = false; return }
        let onRight = left == nil
        if onRight != gloveOnRight {
            gloveOnRight = onRight
            g.scale = onRight ? [-1, 1, 1] : [1, 1, 1]
            setDoubleSided(g)
        }
        g.isEnabled = true
        g.position = h
        let toPitcher = origin - h
        g.orientation = orientation(forward: SIMD3<Float>(toPitcher.x, toPitcher.y * 0.3, toPitcher.z))
    }

    private func setDoubleSided(_ e: Entity) {
        if let m = e as? ModelEntity, let mats = m.model?.materials {
            m.model?.materials = mats.map { mat in
                if var p = mat as? PhysicallyBasedMaterial { p.faceCulling = .none; return p }
                return mat
            }
        }
        e.children.forEach { setDoubleSided($0) }
    }

    func update(dt: Float, time: Double, tracker: MotionTracker) {
        sway.add(tracker.head)
        sparkles.update(dt: dt)
        // glide the pitcher's spot to its next position
        origin += (portalTarget - origin) * min(1, dt * 3)
        portal.position = origin
        portal.orientation = yawToward(simd_normalize(SIMD3<Float>(centre.x - origin.x, 0, centre.z - origin.z)))

        let hands = [tracker.leftHand, tracker.rightHand]
        updateGlove(tracker.leftHand, tracker.rightHand)
        for (i, h) in hands.enumerated() {
            let gloved = glove != nil && ((i == 0 && !gloveOnRight) || (i == 1 && gloveOnRight))
            handMarkers[i].isEnabled = h != nil && !gloved
            if let h { handMarkers[i].position = h }
        }
        // switch from the warm-up to single-leg catching
        if !announcedOneLeg && thrown >= warmups && balls.allSatisfy({ $0.done }) {
            announcedOneLeg = true
            feedback = "Great warm-up! Now lift your other foot and catch on one leg"
            SoundManager.shared.say("Nice. Now lift your other foot, and catch on your \(config.injured.short.lowercased()) leg.")
            nextThrow = max(nextThrow, time + 3.0)
            sway.reset()
        }
        if thrown < config.count + warmups && time >= nextThrow - 1.2 && spotForThrow != thrown {
            spotForThrow = thrown
            if thrown > 0 { choosePitcherSpot() }
        }
        if thrown < config.count + warmups && time >= nextThrow && (announcedOneLeg || thrown < warmups) {
            throwBall(time: time, tracker: tracker); nextThrow = time + interval
        }
        for i in balls.indices where !balls[i].done {
            let b = balls[i]
            let u = Float((time - b.t0) / b.flight)
            var p = b.from + (b.to - b.from) * u
            p.y += 0.9 * 4 * u * (1 - u) * 0.5          // gentle arc
            b.e.position = p
            b.e.orientation = simd_quatf(angle: Float(time) * 8, axis: simd_normalize(SIMD3<Float>(1, 0.3, 0)))
            let radius: Float = glove != nil ? 0.17 : 0.15
            if hands.contains(where: { h in h.map { simd_distance($0, p) < radius } ?? false }) {
                catchBall(i)
            } else if u > 1.35 {
                balls[i].done = true
                combo = 0
                feedback = ["So close!", "Next one's yours", "Stay tall, the next one's coming"].randomElement()
                SoundManager.shared.play("sfx_miss", volume: 0.6)
                b.e.removeFromParent()
            }
        }
        if thrown >= config.count + warmups && balls.allSatisfy({ $0.done }) && !finished { finished = true }
    }

    private func catchBall(_ i: Int) {
        guard !balls[i].done else { return }
        balls[i].done = true
        let b = balls[i]
        // Only single-leg catches count toward the score; warm-up catches are practice.
        if announcedOneLeg { score += 1 }
        combo += 1
        feedback = combo >= 3 ? "\(combo) in a row!" : ["Great catch!", "Nice reach!", "Got it!", "Strike out the wobble!"].randomElement()
        SoundManager.shared.playSpatial("sfx_mitt", on: b.e)
        sparkles.burst(at: b.e.position(relativeTo: root), color: combo >= 3 ? Palette.gold : Palette.teal)
        let e = b.e
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); e.removeFromParent() }
    }

    func handleTap(_ entity: Entity) -> Bool {
        var cur: Entity? = entity
        while let c = cur {
            if let i = balls.firstIndex(where: { $0.e === c && !$0.done }) {
                let u = (SessionClock.now - balls[i].t0) / balls[i].flight
                if u > 0.55 { catchBall(i); return true }   // must be close enough to "reach"
                return false
            }
            cur = c.parent
        }
        return false
    }

    var steadiness: Double { sway.score }
    func stop() { finished = true; sparkles.clear(); root.removeFromParent() }
}

/// Session clock shared by games (seconds since the session started).
@MainActor enum SessionClock { static var now: Double = 0 }
