import RealityKit
import UIKit
import simd

/// Brand look shared by the companion and the step effects (moodboard: dawn-blue mirror lake with floating orbs,
/// sunlit leaf shadows over goldfish water, sky lanterns, glowing forest particles). Soft, warm, slow.
@MainActor
enum Brand {
    static let cream = UIColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1)
    static let dawnBlue = UIColor(red: 0.66, green: 0.82, blue: 1.0, alpha: 1)
    static let lilac = UIColor(red: 0.84, green: 0.76, blue: 1.0, alpha: 1)
    static let peach = UIColor(red: 1.0, green: 0.82, blue: 0.7, alpha: 1)
    static let amber = UIColor(red: 1.0, green: 0.74, blue: 0.42, alpha: 1)
    static let firefly = UIColor(red: 0.86, green: 1.0, blue: 0.62, alpha: 1)

    /// The butterfly's light, tuned to each place (wings keep their dawn-blue texture; this is a gentle tint).
    static func companionTint(_ kind: EnvironmentKind) -> UIColor {
        switch kind.flavor {
        case .dawnLake: return .white
        case .riverValley: return UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        case .goldenMeadow: return UIColor(red: 0.95, green: 1.0, blue: 0.88, alpha: 1)
        case .auroraNight: return UIColor(red: 1.0, green: 0.9, blue: 0.78, alpha: 1)
        }
    }

    private static var cache: [String: TextureResource] = [:]
    static func texture(_ name: String) -> TextureResource? {
        if let t = cache[name] { return t }
        guard let u = Bundle.main.url(forResource: name, withExtension: "png"),
              let t = try? TextureResource.load(contentsOf: u) else { return nil }
        cache[name] = t
        return t
    }

    /// Unlit, double-sided sprite material whose shape comes from an alpha texture.
    static func sprite(_ name: String, tint: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let c = texture(name) { m.color = .init(tint: tint, texture: .init(c)) } else { m.color = .init(tint: tint) }
        if let a = texture(name + "_alpha") {
            m.blending = .transparent(opacity: .init(scale: opacity, texture: .init(a)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        m.faceCulling = .none
        return m
    }
}

/// "Lumi", a glowing butterfly that keeps the person company and shows them where to look and step.
/// It hovers where the eyes should rest during balance work, flies ahead to the next pad or stone in the games,
/// circles the room during the safety scan, breathes with the person during rests, lands on an outstretched hand,
/// and does a small happy loop on every rep. It never moves fast or close to the face.
@MainActor
final class ButterflyGuide {
    enum Mode: Equatable {
        case hover(SIMD3<Float>)           // gentle figure-eight around a point
        case guide(SIMD3<Float>)           // fly to a point and hover just above it
        case perch(SIMD3<Float>)           // settle on a point, wings slowly open and close
        case breathe(SIMD3<Float>)         // rest: wings open over 5 s, close over 5 s (6 breaths a minute)
        case circle(SIMD3<Float>, Float)   // fly slowly around a centre at a radius (room scan)
        case land(SIMD3<Float>)            // come down and rest on the floor (after a STOP)
    }

    static let name = "Lumi"
    /// Add `node` to the scene. `root` is the butterfly itself; the dust trail stays in world space beside it.
    let node = Entity()
    let root = Entity()
    private let flyer = Entity()
    private let leftHinge = Entity()
    private let rightHinge = Entity()
    private var wingModels: [ModelEntity] = []
    private let dust = Sparkles()
    private var tint: UIColor = .white

    var mode: Mode = .hover([0, 1.4, -1.2])
    var visible = true { didSet { node.isEnabled = visible; if !visible { dust.clear() } } }
    private(set) var position = SIMD3<Float>(0, 1.4, -1.2)
    private var velocity = SIMD3<Float>(repeating: 0)
    private var flap: Float = 0
    private var openness: Float = 1
    private var loopTimer: Float = 0
    private var dustTimer: Float = 0
    private var circleAngle: Float = 0
    private var perchedOnHand = false

    init() {
        root.name = "Butterfly"
        root.addChild(flyer)
        node.addChild(root)
        node.addChild(dust.root)
        build()
        // tappable: a friendly word and a little loop
        root.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.16)]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
    }

    private func build() {
        let span: Float = 0.12                         // one wing ~12 cm: large and readable, even in the simulator
        let wingMesh = MeshResource.generatePlane(width: span, depth: span)
        let mat = Brand.sprite("butterfly_wing", tint: tint, opacity: 0.95)
        let right = ModelEntity(mesh: wingMesh, materials: [mat])
        right.position = [span / 2, 0, 0]
        let left = ModelEntity(mesh: wingMesh, materials: [mat])
        left.position = [-span / 2, 0, 0]
        left.orientation = simd_quatf(angle: .pi, axis: [0, 0, 1])     // mirror across the body
        rightHinge.addChild(right); leftHinge.addChild(left)
        wingModels = [left, right]
        flyer.addChild(leftHinge); flyer.addChild(rightHinge)
        // slender glowing body and a soft halo so it reads in a bright room too
        let body = ModelEntity(mesh: .generateBox(size: [0.014, 0.014, 0.08], cornerRadius: 0.007),
                               materials: [EnvironmentBuilder.glow(Brand.cream, opacity: 0.95)])
        flyer.addChild(body)
        let halo = ModelEntity(mesh: .generatePlane(width: 0.38, depth: 0.38), materials: [Brand.sprite("glow", tint: Brand.dawnBlue, opacity: 0.5)])
        halo.position = [0, -0.002, 0]
        flyer.addChild(halo)
        for s: Float in [-1, 1] {               // antennae
            let a = ModelEntity(mesh: .generateBox(size: [0.0016, 0.0016, 0.03]), materials: [EnvironmentBuilder.glow(Brand.cream, opacity: 0.8)])
            a.position = [s * 0.006, 0.006, -0.036]
            a.orientation = simd_quatf(angle: s * 0.35, axis: [0, 1, 0]) * simd_quatf(angle: 0.35, axis: [1, 0, 0])
            flyer.addChild(a)
        }
    }

    /// Match the scene's light (called when the place changes).
    func setPlace(_ kind: EnvironmentKind) {
        tint = Brand.companionTint(kind)
        let mat = Brand.sprite("butterfly_wing", tint: tint, opacity: 0.95)
        for w in wingModels { w.model?.materials = [mat] }
    }

    func place(at p: SIMD3<Float>) { position = p; velocity = .zero; root.position = p }

    /// A small happy loop with a shimmer of wing dust (on each rep, landing or game hit).
    func celebrate(color: UIColor) {
        guard visible else { return }
        loopTimer = 1.1
        dust.burst(at: position, color: color, count: 10, speed: 0.25, size: 0.006)
    }

    func update(dt: Float, time: Double, head: SIMD3<Float>, headForward: SIMD3<Float>, hand: SIMD3<Float>?, handFlatness: Float = 1) {
        guard visible else { return }
        dust.update(dt: dt)
        let t = Float(time)
        var target: SIMD3<Float>
        var settle = false
        var speedLimit: Float = 0.55
        // A hand held out in front invites Lumi to land on it (not during the active set). The current mode is kept,
        // so Lumi goes back to her task when the hand drops. With `seekHand` (the "Meet Lumi" step) she looks for a
        // hand anywhere within reach, follows it as it moves, and reports the landing once.
        perchedOnHand = false
        if let h = hand, allowsHand {
            let toHand = h - head
            let dist = simd_length(toHand)
            let inFront = dist > 1e-3 && simd_dot(toHand / dist, headForward) > (seekHand ? -0.2 : 0.5)
            if dist < (seekHand ? 1.1 : 0.75), h.y > head.y - (seekHand ? 1.1 : 0.6), inFront {
                perchedOnHand = true
                handSeen = 0
                lastHand = h
            }
        }
        if !perchedOnHand {
            handSeen += dt
            if handSeen > 1.0 { landedOnHand = false }       // hand gone for a second: next landing is a new one
        }
        switch mode {
        case _ where perchedOnHand:
            // A calm, predictable approach: slow down over the last 30 cm. While seeking, Lumi only lands on a hand
            // held roughly flat; otherwise she waits just above it.
            let flatEnough = !seekHand || handFlatness > 0.55
            target = lastHand + (flatEnough ? [0, 0.012, 0] : [0, 0.14, 0])
            let dist = simd_distance(position, target)
            settle = flatEnough && dist < 0.04
            speedLimit = seekHand ? max(0.1, min(0.45, dist * 1.4)) : 0.9
            if settle && !landedOnHand {
                landedOnHand = true
                dust.burst(at: position, color: Brand.cream, count: 14, speed: 0.25, size: 0.006)
                onLandedOnHand?()
            }
        case .hover(let p):
            target = p + [sin(t * 0.9) * 0.06, sin(t * 1.3) * 0.035, sin(t * 1.8) * 0.025]
        case .guide(let p):
            target = p + [0, 0.3, 0] + [sin(t * 1.1) * 0.03, sin(t * 1.7) * 0.025, 0]
            speedLimit = 0.8
        case .perch(let p), .breathe(let p):
            target = p; settle = simd_distance(position, p) < 0.05
        case .circle(let c, let r):
            circleAngle += dt * (2 * .pi / 22)                // one slow lap in ~22 s
            target = c + [sin(circleAngle) * r, 0.05 * sin(t * 1.4), -cos(circleAngle) * r]
        case .land(let p):
            target = p + [0, 0.02, 0]; settle = simd_distance(position, target) < 0.05; speedLimit = 0.35
        }
        // keep a respectful distance from the face (never closer than 45 cm unless it's on the person's hand)
        if !perchedOnHand {
            let away = target - head
            let d = simd_length(away)
            if d < 0.45 { target = head + (d > 1e-3 ? away / d : headForward) * 0.45 }
        }
        // little loop-de-loop when celebrating
        if loopTimer > 0 {
            loopTimer = max(0, loopTimer - dt)
            let a = (1 - loopTimer / 1.1) * 2 * .pi
            target += [0, (1 - cos(a)) * 0.09, -sin(a) * 0.07]
        }
        // critically damped spring toward the target, with a calm speed limit
        let k: Float = settle ? 30 : 9, damp: Float = settle ? 11 : 5
        velocity += ((target - position) * k - velocity * damp) * dt
        let sp = simd_length(velocity)
        if sp > speedLimit { velocity *= speedLimit / sp }
        position += velocity * dt
        root.position = position
        // face the direction of travel; when hovering, turn side-on to the person so the wings show
        let toPerson = SIMD3<Float>(head.x - position.x, 0, head.z - position.z)
        // hovering: face away from the person, nose tilted up, so they see the open wings from behind
        let flying = sp > 0.12
        let heading = flying ? SIMD3<Float>(velocity.x, 0, velocity.z) : -toPerson
        if simd_length(heading) > 1e-4 {
            let goal = yawToward(simd_normalize(heading))
            let pitch: Float = flying ? 0.35 : 1.05     // hovering: nearly upright so the open wings face the person
            flyer.orientation = simd_slerp(flyer.orientation, goal * simd_quatf(angle: pitch, axis: [1, 0, 0]), min(1, dt * 3))
        }
        // wings: fast, soft flutter in flight; slow open/close when perched; breathing pace during rest
        let angle: Float
        switch mode {
        case _ where perchedOnHand:
            if settle {
                openness += (0.3 - openness) * min(1, dt * 2)
                angle = 1.2 - openness * (0.6 + 0.4 * sin(t * 0.8))
            } else { flap += dt * 2 * .pi * 4; angle = 0.2 + 0.8 * (0.5 + 0.5 * sin(flap)) }
        case .breathe:
            let b = 0.5 - 0.5 * cos(t * 2 * .pi / 10)       // 0 → 1 → 0 over 10 s
            angle = 1.25 - b * 1.1
        case .perch, .land:
            if settle {
                openness += (0.3 - openness) * min(1, dt * 2)
                angle = 1.2 - openness * (0.6 + 0.4 * sin(t * 0.8))
            } else { flap += dt * 2 * .pi * 4; angle = 0.2 + 0.8 * (0.5 + 0.5 * sin(flap)) }
        default:
            flap += dt * 2 * .pi * (3.2 + min(2, sp * 3))
            angle = 0.15 + 0.85 * (0.5 + 0.5 * sin(flap))
        }
        leftHinge.orientation = simd_quatf(angle: -angle, axis: [0, 0, 1])
        rightHinge.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
        flyer.position = [0, settle ? 0 : 0.008 * sin(flap), 0]
        // a faint trail of glowing dust while flying
        dustTimer += dt
        if sp > 0.08, dustTimer > 0.14 {
            dustTimer = 0
            dust.dust(at: position + [0, -0.01, 0], color: Bool.random() ? Brand.cream : Brand.lilac)
        }
    }

    /// Only outside the active set, so it never distracts mid-exercise.
    var allowsHand = true
    /// "Meet Lumi": actively look for the person's hand (wider reach, any height from waist up).
    var seekHand = false
    /// Called once each time Lumi settles on the person's hand.
    var onLandedOnHand: (() -> Void)?
    private(set) var landedOnHand = false
    private var lastHand = SIMD3<Float>(0, 1.2, -0.5)
    private var handSeen: Float = 10

    /// Something kind to say when the person taps Lumi.
    static func tapLine(seed: Int) -> String {
        let lines = [
            "Hi, I'm Lumi. Follow me, I'll show you where to look and where to step.",
            "Slow is smooth. Take all the time you need.",
            "You're doing well. Every steady step counts.",
            "If anything hurts sharply, tap stop. I'll wait right here.",
            "Hold out your hand and I'll come and rest on it."
        ]
        return lines[abs(seed) % lines.count]
    }

    func contains(_ e: Entity) -> Bool {
        var x: Entity? = e
        while let c = x { if c === root { return true }; x = c.parent }
        return false
    }

    func clear() { dust.clear() }
}
