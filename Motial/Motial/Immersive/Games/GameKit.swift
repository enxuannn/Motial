import RealityKit
import UIKit
import simd

/// Common interface for the rehab games. Each game delivers a guideline exercise; the game layer adds goals,
/// feedback and encouragement (the "Optimism" part of PEACE & LOVE).
@MainActor
protocol RehabGame: AnyObject {
    var root: Entity { get }
    var score: Int { get }
    var finished: Bool { get }
    var status: String { get }
    var feedback: String? { get }
    func start(tracker: MotionTracker)
    func update(dt: Float, time: Double, tracker: MotionTracker)
    func handleTap(_ entity: Entity) -> Bool
    func stop()
    /// Where the person should step or look next (the companion butterfly flies there). nil = no specific spot.
    var guidePoint: SIMD3<Float>? { get }
    /// Games that put you somewhere else (the cockpit drive) hide the coach while they run.
    var hidesCoach: Bool { get }
    /// Big, glanceable numbers for the game HUD (pedal games).
    var stats: [GameStat] { get }
    /// Live accelerator level 0…1 (pedal games), shown as a bar.
    var pedalLevel: Float? { get }
    /// What the ankle is doing right now, in plain words (learning moment).
    var learnTip: String? { get }
    /// Result for the "Your drives" records (pedal games).
    var summary: GameSummary? { get }
    /// Called when the session is paused or resumed (stop looping sounds, freeze animation).
    func setPaused(_ paused: Bool)
}

struct GameStat: Hashable {
    let value: String
    let label: String
    var progress: Double? = nil
}

extension RehabGame {
    var guidePoint: SIMD3<Float>? { nil }
    var hidesCoach: Bool { false }
    var stats: [GameStat] { [] }
    var pedalLevel: Float? { nil }
    var learnTip: String? { nil }
    var summary: GameSummary? { nil }
    func setPaused(_ paused: Bool) {}
}

struct GameConfig {
    var level: Int = 1                 // 1 – 3 from the adaptation engine
    var hops = false                   // hop variant (return-to-activity stage only)
    var count = 8                      // throws / notes / stones depending on game
    var injured: AnkleSide = .right
    var song: SongChoice = .bundled("music_step_up", bpm: 104)
    var environment: EnvironmentKind = .dawnLake
    var setNumber = 1                  // 1-based set within the exercise
    var rhythmMode: RhythmMode = .step
    var fallRisk = false               // 65+ or a fall in the past year: gentler variants
    var seated = false                 // seated variant (Lantern Glide steered by the iPhone companion)
    var reduceMotion = false           // Settings › Reduce motion: slower cockpit drive
    var coachAnchor: SIMD3<Float>? = nil  // where the 3D coach stands (Word Garden shows the letter beside them)
}

/// Rhythm Steps variants, chosen by stage (see ClinicalEngine.rhythmMode).
/// shift: feet stay planted, lean toward the pad holding a support (weight transfer, stage 2)
/// step:  step onto the pad and back (stages 2–4)
/// hop:   single-leg hop onto the pad (stage 4, clinician-cleared)
enum RhythmMode: String { case shift, step, hop }

/// Feedback that belongs to the place the person chose: ripples on the lake, droplets on the river,
/// flowers in the meadow, shooting stars under the aurora. Every hit changes the world a little.
@MainActor
final class WorldReactor {
    let root = Entity()
    let kind: EnvironmentKind
    private struct Anim {
        let e: Entity; var t: Float; let life: Float; let grow: SIMD3<Float>; let rise: Float; let keep: Bool
        var vel = SIMD3<Float>(repeating: 0)   // drift (leaf petals)
        var spin: Float = 0                    // radians per second around Y
        var sprite: String? = nil              // textured sprite: fade keeps its alpha shape
        var tint: UIColor = .white
        var peak: Float = 1                    // starting opacity
    }
    private var anims: [Anim] = []
    private var flowers = 0
    let sparkles = Sparkles()

    init(_ kind: EnvironmentKind) { self.kind = kind; root.addChild(sparkles.root) }

    var colors: [UIColor] { Self.colors(kind) }
    static func colors(_ kind: EnvironmentKind) -> [UIColor] {
        switch kind.flavor {
        // soft, warm palettes from the moodboard (no saturated neon)
        case .dawnLake: return [UIColor(red: 0.72, green: 0.86, blue: 1.0, alpha: 1), UIColor(red: 0.93, green: 0.82, blue: 1.0, alpha: 1), UIColor(red: 1.0, green: 0.9, blue: 0.78, alpha: 1)]
        case .riverValley: return [UIColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 1), UIColor(red: 0.7, green: 0.92, blue: 0.62, alpha: 1), UIColor(red: 1.0, green: 0.7, blue: 0.45, alpha: 1)]
        case .goldenMeadow: return [UIColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 1), UIColor(red: 1.0, green: 0.78, blue: 0.82, alpha: 1), UIColor(red: 0.85, green: 0.95, blue: 0.7, alpha: 1)]
        case .auroraNight: return [RhythmStepGame.lanternWarm, UIColor(red: 1.0, green: 0.82, blue: 0.55, alpha: 1), UIColor(red: 0.95, green: 0.6, blue: 0.35, alpha: 1)]
        }
    }
    var hitSound: String {
        switch kind.flavor {
        case .dawnLake: return "sfx_chime"
        case .riverValley: return "sfx_drop"
        case .goldenMeadow: return "sfx_bird"
        case .auroraNight: return "sfx_shimmer"
        }
    }
    func praise(_ combo: Int) -> String? {
        guard combo > 0, combo % 5 == 0 else { return nil }
        switch kind.flavor {
        case .dawnLake: return "The lake is glowing. \(combo) calm steps"
        case .riverValley: return "The goldfish are dancing. \(combo) in a row"
        case .goldenMeadow: return "The meadow is blooming. \(combo) in a row"
        case .auroraNight: return "\(combo) lanterns in the sky"
        }
    }

    /// React at a floor position (y ignored) with strength 0…1. Art direction (moodboard): soft glow, slow motion,
    /// warm light: orbs over a mirror lake, a goldfish in sunlit water, fireflies in the meadow, sky lanterns at night.
    func react(at p: SIMD3<Float>, strength: Float, colorIndex: Int) {
        let c = colors[colorIndex % colors.count]
        let floor = SIMD3<Float>(p.x, 0.01, p.z)
        brandBloom(at: floor, color: c, strength: strength)
        switch kind.flavor {
        case .dawnLake:   // ripples on the mirror lake, and a glowing orb rises and floats there
            for k in 0..<2 {
                guard let ring = EnvironmentBuilder.annulus(inner: 0.14, outer: 0.155) else { break }
                let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(c, opacity: 0.7)])
                r.position = floor + [0, Float(k) * 0.002, 0]
                root.addChild(r)
                anims.append(Anim(e: r, t: -Float(k) * 0.35, life: 2.4, grow: [2.4 + strength, 0, 2.4 + strength], rise: 0, keep: false))
            }
            let orb = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [EnvironmentBuilder.glow(UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1), opacity: 0.9)])
            orb.position = floor + [Float.random(in: -0.2...0.2), 0.2, Float.random(in: -0.2...0.2)]
            root.addChild(orb)
            anims.append(Anim(e: orb, t: 0, life: 9, grow: [1, 1, 1], rise: 0.18, keep: false))
        case .riverValley: // a little goldfish leaps from the sunlit water and splashes back
            fish.append(Fish(e: Self.makeGoldfish(), from: floor, to: floor + [Float.random(in: -0.35...0.35), 0, Float.random(in: -0.45 ... -0.2)], t: 0))
            root.addChild(fish[fish.count - 1].e)
            sparkles.burst(at: floor + [0, 0.03, 0], color: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), count: 8 + Int(strength * 8), speed: 0.6, size: 0.008)
        case .goldenMeadow: // a flower sprouts where you stepped, fireflies drift up, the meadow fills over the song
            let stem = ModelEntity(mesh: .generateBox(size: [0.008, 0.16, 0.008]), materials: [EnvironmentBuilder.glow(Palette.mint, opacity: 0.9)])
            stem.position = [0, 0.08, 0]
            let head = ModelEntity(mesh: .generateSphere(radius: 0.028), materials: [EnvironmentBuilder.glow(c, opacity: 0.95)])
            head.position = [0, 0.17, 0]
            let f = Entity(); f.addChild(stem); f.addChild(head)
            let ang = Float.random(in: 0...(2 * .pi)), rad = Float.random(in: 0.25...0.55)
            f.position = floor + [cos(ang) * rad, 0, sin(ang) * rad]
            f.scale = [0.01, 0.01, 0.01]
            root.addChild(f)
            anims.append(Anim(e: f, t: 0, life: 1.2, grow: [1, 1, 1], rise: 0, keep: true))
            flowers += 1
            if flowers > 40, let old = anims.first(where: { $0.keep }) { old.e.removeFromParent(); anims.removeAll { $0.e === old.e } }
            for _ in 0..<(3 + Int(strength * 4)) {
                sparkles.drift(around: floor + [0, 0.2, 0], color: UIColor(red: 1, green: 0.93, blue: 0.55, alpha: 1), radius: 0.4)
            }
        case .auroraNight:  // release a sky lantern that floats slowly up into the night
            let l = RhythmStepGame.makeLantern(scale: 0.8)
            l.position = floor + [0, 0.25, 0]
            root.addChild(l)
            anims.append(Anim(e: l, t: 0, life: 18, grow: [1, 1, 1], rise: 0.22, keep: false))
            sparkles.burst(at: floor + [0, 0.1, 0], color: RhythmStepGame.lanternWarm, count: 8, speed: 0.35)
        }
    }

    /// Steady's signature step: a soft pool of light opens under the foot and a few sunlit leaves drift
    /// outward and settle, like the leaf shadows in the brand moodboard. Same in every place, tinted to it.
    private func brandBloom(at floor: SIMD3<Float>, color c: UIColor, strength: Float) {
        let pool = ModelEntity(mesh: .generatePlane(width: 0.42, depth: 0.42), materials: [Brand.sprite("glow", tint: c, opacity: 0.55)])
        pool.position = floor + [0, 0.002, 0]
        root.addChild(pool)
        anims.append(Anim(e: pool, t: 0, life: 1.8, grow: [1.8 + strength * 0.6, 0, 1.8 + strength * 0.6], rise: 0, keep: false, sprite: "glow", tint: c, peak: 0.55))
        let n = 3 + Int(strength * 3)
        let start = Float.random(in: 0...(2 * .pi))
        for i in 0..<n {
            let a = start + Float(i) / Float(n) * 2 * .pi + Float.random(in: -0.3...0.3)
            let dir = SIMD3<Float>(cos(a), 0, sin(a))
            let leafTint = i % 2 == 0 ? Brand.cream : c
            let leaf = ModelEntity(mesh: .generatePlane(width: 0.045, depth: 0.065), materials: [Brand.sprite("leaf", tint: leafTint, opacity: 0.8)])
            leaf.position = floor + dir * 0.08 + [0, 0.004 + Float(i) * 0.001, 0]
            leaf.orientation = simd_quatf(angle: -a + .pi / 2, axis: [0, 1, 0])
            root.addChild(leaf)
            anims.append(Anim(e: leaf, t: -Float(i) * 0.05, life: 2.6, grow: [1, 1, 1], rise: 0, keep: false,
                              vel: dir * Float.random(in: 0.09...0.15), spin: Float.random(in: -0.8...0.8), sprite: "leaf", tint: leafTint, peak: 0.8))
        }
    }

    private struct Fish { let e: Entity; let from: SIMD3<Float>; let to: SIMD3<Float>; var t: Float }
    private var fish: [Fish] = []

    static func makeGoldfish() -> Entity {
        let e = Entity()
        let orange = UIColor(red: 1, green: 0.48, blue: 0.15, alpha: 1)
        let body = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [EnvironmentBuilder.glow(orange, opacity: 0.95)])
        body.scale = [0.7, 0.7, 1.4]
        let tail = ModelEntity(mesh: .generateBox(size: [0.004, 0.045, 0.035], cornerRadius: 0.002), materials: [EnvironmentBuilder.glow(UIColor(red: 1, green: 0.7, blue: 0.4, alpha: 1), opacity: 0.85)])
        tail.position = [0, 0, 0.05]
        e.addChild(body); e.addChild(tail)
        return e
    }

    func update(dt: Float) {
        sparkles.update(dt: dt)
        // goldfish arcs: 1.1 s leap, then a ripple where it lands
        var swimming: [Fish] = []
        for var f in fish {
            f.t += dt / 1.1
            if f.t >= 1 {
                f.e.removeFromParent()
                if let ring = EnvironmentBuilder.annulus(inner: 0.06, outer: 0.075) {
                    let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(UIColor(red: 1, green: 0.9, blue: 0.65, alpha: 1), opacity: 0.7)])
                    r.position = [f.to.x, 0.012, f.to.z]; root.addChild(r)
                    anims.append(Anim(e: r, t: 0, life: 1.6, grow: [3, 0, 3], rise: 0, keep: false))
                }
                continue
            }
            var p = f.from + (f.to - f.from) * f.t
            p.y = 0.02 + 0.32 * 4 * f.t * (1 - f.t)
            f.e.position = p
            let dir = simd_normalize(f.to - f.from + [0, 0.0001, 0])
            let pitch = (0.5 - f.t) * 1.6
            f.e.orientation = orientation(forward: SIMD3<Float>(-dir.x, pitch, -dir.z))
            swimming.append(f)
        }
        fish = swimming
        var keep: [Anim] = []
        for var a in anims {
            a.t += dt
            if a.t < 0 { keep.append(a); continue }
            let u = min(1, a.t / a.life)
            if a.keep {
                let s = 0.01 + 0.99 * (1 - pow(1 - u, 3))
                a.e.scale = [s, s, s]
                keep.append(a); continue
            }
            if u >= 1 { a.e.removeFromParent(); continue }
            a.e.scale = SIMD3<Float>(repeating: 1) + (a.grow - SIMD3<Float>(repeating: 1)) * u * SIMD3<Float>(a.grow.x > 0 ? 1 : 0, a.grow.y > 0 ? 1 : 0, a.grow.z > 0 ? 1 : 0)
            if a.rise > 0 { a.e.position.y += a.rise * dt }
            if simd_length(a.vel) > 0 { a.e.position += a.vel * dt * (1 - u) }          // drift, easing to a stop
            if a.spin != 0 { a.e.orientation = simd_quatf(angle: a.spin * dt * (1 - u), axis: [0, 1, 0]) * a.e.orientation }
            if let sprite = a.sprite, let m = a.e as? ModelEntity {
                let fade = u < 0.15 ? u / 0.15 : (1 - u) / 0.85                       // quick fade in, slow fade out
                m.model?.materials = [Brand.sprite(sprite, tint: a.tint, opacity: a.peak * max(0, fade))]
            } else if let m = a.e as? ModelEntity, var mat = m.model?.materials.first as? UnlitMaterial {
                mat.blending = .transparent(opacity: .init(floatLiteral: max(0, 1 - u)))
                m.model?.materials = [mat]
            }
            keep.append(a)
        }
        anims = keep
    }

    func clear() { sparkles.clear(); Array(root.children).forEach { $0.removeFromParent() }; anims.removeAll(); root.addChild(sparkles.root) }
}

/// Rotation whose local +Z points along `forward` with +Y as close to `up` as possible.
func orientation(forward: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_quatf {
    let z = simd_normalize(forward)
    var x = simd_cross(up, z)
    if simd_length(x) < 1e-4 { x = [1, 0, 0] }
    x = simd_normalize(x)
    let y = simd_cross(z, x)
    return simd_quatf(simd_float3x3(columns: (x, y, z)))
}

enum SongChoice: Equatable {
    case bundled(String, bpm: Double)
    case imported(ImportedSong)

    var bpm: Double {
        switch self { case .bundled(_, let b): return b; case .imported(let s): return s.bpm }
    }
    var firstBeat: Double {
        switch self { case .bundled: return 0; case .imported(let s): return s.firstBeat }
    }
    var title: String {
        switch self {
        case .bundled(let n, _):
            switch n {
            case "music_calm_flow": return "Calm Flow"
            case "music_night_pulse": return "Night Pulse"
            default: return "Step Up"
            }
        case .imported(let s): return s.title
        }
    }
    var url: URL? {
        switch self {
        case .bundled(let n, _): return Bundle.main.url(forResource: n, withExtension: "m4a")
        case .imported(let s): return AppModel.documents.appendingPathComponent(s.fileName)
        }
    }
    static let bundledTracks: [SongChoice] = [.bundled("music_calm_flow", bpm: 84), .bundled("music_step_up", bpm: 104), .bundled("music_night_pulse", bpm: 122)]
}

/// Tiny particle system made of glowing spheres (no external assets).
@MainActor
final class Sparkles {
    struct P { let e: ModelEntity; var v: SIMD3<Float>; var life: Float; let maxLife: Float }
    let root = Entity()
    private var ps: [P] = []

    func burst(at p: SIMD3<Float>, color: UIColor, count: Int = 18, speed: Float = 1.2, size: Float = 0.012) {
        for _ in 0..<count {
            var m = UnlitMaterial(color: color)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            let e = ModelEntity(mesh: .generateSphere(radius: size * Float.random(in: 0.6...1.3)), materials: [m])
            e.position = p
            root.addChild(e)
            let dir = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -0.2...1.2), Float.random(in: -1...1)))
            let life = Float.random(in: 0.6...1.1)
            ps.append(P(e: e, v: dir * speed * Float.random(in: 0.5...1.0), life: life, maxLife: life))
        }
    }

    /// Slow rising motes (fireflies / pollen).
    func drift(around p: SIMD3<Float>, color: UIColor, radius: Float = 0.5) {
        var m = UnlitMaterial(color: color)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        let e = ModelEntity(mesh: .generateSphere(radius: Float.random(in: 0.006...0.012)), materials: [m])
        e.position = p + SIMD3<Float>(Float.random(in: -radius...radius), Float.random(in: -0.1...0.2), Float.random(in: -radius...radius))
        root.addChild(e)
        let life = Float.random(in: 2.0...3.5)
        ps.append(P(e: e, v: [Float.random(in: -0.05...0.05), Float.random(in: 0.08...0.18), Float.random(in: -0.05...0.05)], life: life, maxLife: life))
    }

    /// A single mote of glowing wing dust that drifts slowly down and fades.
    func dust(at p: SIMD3<Float>, color: UIColor) {
        var m = UnlitMaterial(color: color)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        let e = ModelEntity(mesh: .generateSphere(radius: Float.random(in: 0.0025...0.0045)), materials: [m])
        e.position = p
        root.addChild(e)
        let life = Float.random(in: 1.6...2.4)
        ps.append(P(e: e, v: [Float.random(in: -0.02...0.02), Float.random(in: -0.07 ... -0.03), Float.random(in: -0.02...0.02)], life: life, maxLife: life))
    }

    func update(dt: Float) {
        var keep: [P] = []
        for var p in ps {
            p.life -= dt
            if p.life <= 0 { p.e.removeFromParent(); continue }
            p.v.y -= 0.6 * dt * (p.maxLife < 1.5 ? 1 : 0)
            p.e.position += p.v * dt
            let s = max(0.05, p.life / p.maxLife)
            p.e.scale = [s, s, s]
            keep.append(p)
        }
        ps = keep
    }

    func clear() { ps.forEach { $0.e.removeFromParent() }; ps.removeAll() }
}

enum Palette {
    static let teal = UIColor(red: 0.30, green: 0.85, blue: 0.85, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1)
    static let pink = UIColor(red: 1.0, green: 0.60, blue: 0.75, alpha: 1)
    static let mint = UIColor(red: 0.45, green: 1.0, blue: 0.70, alpha: 1)
    static let violet = UIColor(red: 0.65, green: 0.50, blue: 1.0, alpha: 1)
    static let water = UIColor(red: 0.25, green: 0.55, blue: 0.80, alpha: 1)
}

/// Helper: yaw-only rotation that turns -Z toward a horizontal forward vector.
func yawToward(_ f: SIMD3<Float>) -> simd_quatf {
    let a = atan2(-f.x, -f.z)
    return simd_quatf(angle: a, axis: [0, 1, 0])
}
