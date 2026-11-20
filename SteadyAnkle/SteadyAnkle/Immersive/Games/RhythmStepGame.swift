import RealityKit
import UIKit
import AVFoundation
import simd

/// Calm, rehab-paced stepping to a song the person chooses (art direction: soft glow, floating lanterns,
/// sunlit water, fireflies; never flashing). Notes come at least 2–3 s apart, every 6 notes there is a
/// breathing pause, timing is forgiving, and misses are never punished.
/// Dance-pad style stepping to the beat of a song the person chooses. Pads are front, left and right only
/// (no blind backward steps). Three variants by stage: weight-shift (feet planted, holding a support, like a
/// clinic balance platform), step, and clinician-cleared hop. Every hit makes the chosen world react:
/// ripples on the lake, droplets on the river, flowers in the meadow, shooting stars under the aurora.
@MainActor
final class RhythmStepGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var status: String { (mode == .shift ? "Lean · " : (mode == .hop ? "Hop · " : "")) + "Combo \(combo) · \(hits)/\(notes.count)" }

    private struct Note { let time: Double; let pad: Int; var judged = false }
    private let config: GameConfig
    private var notes: [Note] = []
    private var pads: [ModelEntity] = []
    private var approach: [ModelEntity] = []
    private var dirs: [SIMD2<Float>] = []
    private var lanterns: [(e: Entity, base: SIMD3<Float>, phase: Float)] = []
    private var centre = SIMD2<Float>(0, 0)
    private var player: AVAudioPlayer?
    private var startTime: Double = 0
    private var combo = 0
    private var hits = 0
    private let sparkles = Sparkles()
    private var energy: Float = 0
    private let world: WorldReactor
    private var colors: [UIColor] { world.colors }

    init(config: GameConfig) { self.config = config; self.world = WorldReactor(config.environment) }

    private var mode: RhythmMode { config.rhythmMode }
    /// Minimum time between steps: rehab pace, not a workout.
    private var minInterval: Double {
        switch mode {
        case .shift: return 3.0
        case .hop: return 3.2
        case .step: return config.fallRisk ? 3.0 : [2.8, 2.4, 2.1][max(0, min(2, config.level - 1))]
        }
    }
    private var beatsPerNote: Int {
        let beat = 60 / max(40, config.song.bpm)
        return max(2, Int(ceil(minInterval / beat)))
    }
    /// Timing window (s): generous, so nobody rushes a healing ankle.
    private let window = 0.6
    /// How far the head must move toward a pad to count: a lean, a step or a hop.
    private var threshold: Float { mode == .shift ? 0.05 : (mode == .hop ? 0.14 : 0.11) }

    func start(tracker: MotionTracker) {
        root.addChild(sparkles.root)
        root.addChild(world.root)
        let f = SIMD2<Float>(tracker.headForward.x, tracker.headForward.z)
        let r = SIMD2<Float>(-f.y, f.x)   // right-hand side
        dirs = [f, -r, r]
        centre = [tracker.centre.x, tracker.centre.z]
        // pads (r 0.13 m) sit clear of the centre ring (r 0.15 m) and of each other
        let reach: Float = mode == .hop ? 0.5 : (mode == .shift ? 0.36 : 0.45)
        // centre ring
        if let ring = EnvironmentBuilder.annulus(inner: 0.13, outer: 0.155) {
            let c = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(.white, opacity: 0.7)])
            c.position = [centre.x, 0.006, centre.y]
            root.addChild(c)
        }
        for (i, d) in dirs.enumerated() {
            let p = centre + d * reach
            if let disc = EnvironmentBuilder.annulus(inner: 0, outer: 0.13) {
                let pad = ModelEntity(mesh: disc, materials: [EnvironmentBuilder.glow(colors[i], opacity: 0.25)])
                pad.position = [p.x, 0.005, p.y]
                root.addChild(pad); pads.append(pad)
            }
            if let ring = EnvironmentBuilder.annulus(inner: 0.13, outer: 0.155) {
                let a = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(colors[i], opacity: 0.9)])
                a.position = [p.x, 0.008, p.y]; a.isEnabled = false
                root.addChild(a); approach.append(a)
            }
        }
        // floating paper lanterns drifting around the person (they glow softly and brighten with progress)
        for k in 0..<12 {
            let a = Float(k) / 12 * 2 * .pi + Float.random(in: -0.1...0.1)
            let r = Float.random(in: 2.6...3.6)
            let base = SIMD3<Float>(centre.x + sin(a) * r, Float.random(in: 1.4...2.6), centre.y - cos(a) * r)
            let l = Self.makeLantern()
            l.position = base
            root.addChild(l); lanterns.append((l, base, Float.random(in: 0...(2 * .pi))))
        }
        // chart
        let bpm = config.song.bpm
        let beat = 60 / bpm
        let lead = 4.0 * beat
        var last = -1
        var beatIndex = 0
        for n in 0..<config.count {
            var pad = Int.random(in: 0..<3)
            if pad == last { pad = (pad + 1) % 3 }
            last = pad
            if n > 0 && n % 6 == 0 { beatIndex += Int(ceil(6.0 / beat)) }   // ~6 s breathing pause
            notes.append(Note(time: config.song.firstBeat + lead + Double(beatIndex) * beat, pad: pad))
            beatIndex += beatsPerNote
        }
        if let u = config.song.url { player = SoundManager.shared.playMusic(url: u, loop: true) }
        startTime = SessionClock.now
    }

    private var songTime: Double { player?.currentTime ?? (SessionClock.now - startTime) }

    func update(dt: Float, time: Double, tracker: MotionTracker) {
        sparkles.update(dt: dt)
        world.update(dt: dt)
        let t = songTime
        let beat = 60 / config.song.bpm
        let here = SIMD2<Float>(tracker.head.x, tracker.head.z) - centre
        // lanterns bob slowly; a slow "breathing" glow (0.1 Hz) instead of beat flashing
        energy = max(0, energy - dt * 0.25)
        let progress = Float(hits) / Float(max(1, notes.count))
        for (k, l) in lanterns.enumerated() {
            let bob = sin(Float(t) * 0.6 + l.phase) * 0.06
            l.e.position = l.base + [0, bob, 0]
            l.e.orientation = simd_quatf(angle: Float(t) * 0.15 + l.phase, axis: [0, 1, 0])
            let breath = 0.5 + 0.5 * sin(Float(t) * 0.63 + Float(k))
            if let glow = l.e.children.first as? ModelEntity {
                glow.model?.materials = [EnvironmentBuilder.glow(Self.lanternWarm, opacity: min(1, 0.45 + 0.25 * breath + 0.3 * progress + 0.2 * energy))]
            }
        }
        if let rest = upcomingPauseText(t: t, beat: beat) { feedback = rest }
        // approach rings: shrink during the beat before the note
        for a in approach { a.isEnabled = false }
        for n in notes where !n.judged {
            let lead = n.time - t
            if lead < beat * 1.5 && lead > -0.4 {
                let s = Float(max(1, 1 + lead / (beat * 1.5) * 1.2))
                approach[n.pad].isEnabled = true
                approach[n.pad].scale = [s, 1, s]
            }
        }
        for i in notes.indices where !notes[i].judged {
            let n = notes[i]
            let dt0 = t - n.time
            if dt0 < -0.35 { break }
            let proj = simd_dot(here, dirs[n.pad])
            if proj > threshold && abs(dt0) <= window {
                notes[i].judged = true
                hits += 1; combo += 1
                let grade = abs(dt0) <= 0.2 ? "Lovely" : (abs(dt0) <= 0.4 ? "Nice" : "Good")
                score += grade == "Lovely" ? 3 : (grade == "Nice" ? 2 : 1)
                feedback = world.praise(combo) ?? (combo >= 5 ? "\(grade)! Combo \(combo)" : "\(grade)!")
                energy = min(1, energy + 0.35)
                SoundManager.shared.play(world.hitSound, volume: grade == "Lovely" ? 0.7 : 0.5)
                world.react(at: pads[n.pad].position, strength: grade == "Lovely" ? 1 : (grade == "Nice" ? 0.6 : 0.3), colorIndex: n.pad)
            } else if dt0 > window {
                notes[i].judged = true
                combo = 0
                feedback = mode == .shift ? "Lean a little toward the glowing pad" : "No rush. The next one is coming"
            }
        }
        if notes.allSatisfy({ $0.judged }) && !finished {
            finished = true
            SoundManager.shared.play("sfx_levelup", volume: 0.8)
        }
    }

    static let lanternWarm = UIColor(red: 1.0, green: 0.68, blue: 0.35, alpha: 1)

    /// Paper sky lantern: warm glowing body with a darker rim and a tiny flame.
    static func makeLantern(scale: Float = 1) -> Entity {
        let e = Entity()
        let body = ModelEntity(mesh: .generateBox(size: [0.16 * scale, 0.22 * scale, 0.16 * scale], cornerRadius: 0.03 * scale),
                               materials: [EnvironmentBuilder.glow(lanternWarm, opacity: 0.6)])
        e.addChild(body)
        let rim = ModelEntity(mesh: .generateBox(size: [0.13 * scale, 0.012 * scale, 0.13 * scale]),
                              materials: [EnvironmentBuilder.glow(UIColor(red: 0.45, green: 0.22, blue: 0.1, alpha: 1), opacity: 0.9)])
        rim.position.y = -0.11 * scale
        e.addChild(rim)
        let flame = ModelEntity(mesh: .generateSphere(radius: 0.018 * scale),
                                materials: [EnvironmentBuilder.glow(UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))])
        flame.position.y = -0.08 * scale
        e.addChild(flame)
        return e
    }

    /// A soft cue a few seconds into each breathing pause.
    private func upcomingPauseText(t: Double, beat: Double) -> String? {
        guard let next = notes.first(where: { !$0.judged }), let lastDone = notes.last(where: { $0.judged }) else { return nil }
        if next.time - lastDone.time > 5, t > lastDone.time + 0.8, t < next.time - 1.5 {
            return "Breathe… shake out your ankle. Next steps in \(Int(next.time - t)) s"
        }
        return nil
    }

    func handleTap(_ entity: Entity) -> Bool { false }

    /// The pad of the next note coming up (the butterfly hovers over it a beat or two ahead).
    var guidePoint: SIMD3<Float>? {
        let t = songTime, beat = 60 / config.song.bpm
        guard let n = notes.first(where: { !$0.judged }), n.time - t < beat * 4, pads.indices.contains(n.pad) else { return nil }
        return pads[n.pad].position
    }
    func stop() {
        finished = true
        SoundManager.shared.stopMusic()
        sparkles.clear(); world.clear(); root.removeFromParent()
    }
}
