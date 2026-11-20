import RealityKit
import UIKit
import simd

/// Stepping stones across a river laid on the real floor, played as levels (like an agility ladder).
/// Step mode (Load / Balance stage): L1 straight path → L2 zig-zag → L3 side-step crossing (lateral weight transfer).
/// Hop mode (Return to Activity, clinician-cleared; MGH phase IV): first set at level 1 is a two-foot warm-up
/// (MGH phase III starts with double-leg hops), then single-leg: L1 forward hops → L2 zig-zag hops →
/// L3 quarter-turn hops (change of direction). Every landing must be "stuck" before the next stone lights up.
@MainActor
final class RiverStonesGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var status: String {
        if returning { return "Walk back to the start ring" }
        return "Level \(level) · \(levelName) · Stone \(min(index, stones.count)) of \(stones.count)"
    }

    private var level: Int { max(1, min(3, config.level)) }
    /// Two-foot hops for the first set of the first hop level (double-leg before single-leg).
    private var twoFoot: Bool { config.hops && level == 1 && config.setNumber == 1 }
    private var quarterTurns: Bool { config.hops && level == 3 }
    private var sideSteps: Bool { !config.hops && level == 3 }
    var levelName: String {
        if config.hops { return twoFoot ? "Two-foot warm-up" : ["Forward hops", "Zig-zag hops", "Quarter-turn hops"][level - 1] }
        return ["Straight path", "Zig-zag path", "Side-step crossing"][level - 1]
    }

    private let config: GameConfig
    private var stones: [(entity: Entity, centre: SIMD2<Float>)] = []
    private var index = 0
    private var dwell: Float = 0
    private var hop = HopDetector()
    private var landedAt: Double?
    private var landingSway = SwayMeter()
    private var returning = false
    private var startRing = Entity()
    private var startCentre = SIMD2<Float>(0, 0)
    private let sparkles = Sparkles()
    private var goal = Entity()
    private var rounds = 0

    init(config: GameConfig) { self.config = config }

    private var stoneCount: Int { config.fallRisk ? 5 : [5, 6, 7][level - 1] }
    private var spacing: Float {
        if config.hops { return quarterTurns ? 0.34 : [0.36, 0.38, 0.34][level - 1] }
        return sideSteps ? 0.30 : 0.48
    }
    private var zig: Float {
        if config.hops { return [0.04, 0.2, 0.06][level - 1] }
        return [0.06, 0.16, 0.22][level - 1]
    }
    private var targetYaw: [Float] = []        // quarter-turn level: heading to land in, per stone
    private var startYaw: Float = 0

    func start(tracker: MotionTracker) {
        root.addChild(sparkles.root)
        hop.baseline = tracker.standingHeight
        let f = tracker.headForward
        startYaw = atan2(f.x, -f.z)
        if twoFoot { feedback = "Warm-up: small two-foot hops across" }
        else if config.hops { feedback = "Hop on your \(config.injured.short.lowercased()) leg and stick each landing" }
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        let c = tracker.centre
        startCentre = [c.x, c.z]
        let length = spacing * Float(stoneCount + 1)
        // water surface
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: Palette.water)
        water.roughness = .init(floatLiteral: 0.08)
        water.metallic = .init(floatLiteral: 0.2)
        water.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let plane = ModelEntity(mesh: .generatePlane(width: 1.3, depth: length, cornerRadius: 0.25), materials: [water])
        plane.position = c + f * (length / 2 + 0.25) + [0, 0.004, 0]
        plane.orientation = yawToward(f)
        root.addChild(plane)
        // start ring
        if let ring = EnvironmentBuilder.annulus(inner: 0.2, outer: 0.24) {
            let r = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.mint, opacity: 0.85)])
            startRing.addChild(r)
        }
        startRing.position = c + [0, 0.006, 0]
        root.addChild(startRing)
        // stones
        Task { @MainActor in
            let template = try? await Entity(named: "Stones", in: .main)
            let variants = ["Stone_A", "Stone_B", "Stone_C"].compactMap { template?.findEntity(named: $0) }
            for i in 0..<self.stoneCount {
                let side: Float = i % 2 == 0 ? -1 : 1
                let along = self.spacing * Float(i + 1) + 0.25
                let p = c + f * along + right * side * self.zig * Float.random(in: 0.7...1.0)
                let stone: Entity
                if let v = variants.randomElement() {
                    stone = v.clone(recursive: true)
                    stone.position = .zero
                } else {
                    var m = PhysicallyBasedMaterial(); m.baseColor = .init(tint: .gray)
                    stone = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.2), materials: [m])
                }
                let holder = Entity()
                holder.position = [p.x, 0, p.z]
                holder.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: [0, 1, 0])
                stone.scale = [0.85, 0.18, 0.85]
                holder.addChild(stone)
                if self.quarterTurns {
                    // arrow on the stone: land facing a quarter turn left or right
                    let turn: Float = i % 2 == 0 ? .pi / 2 : 0
                    let yaw = self.startYaw + (i % 4 == 0 ? turn : (i % 4 == 2 ? -turn : 0))
                    self.targetYaw.append(yaw)
                    let arrow = Entity()
                    let shaft = ModelEntity(mesh: .generateBox(size: [0.03, 0.006, 0.16], cornerRadius: 0.003), materials: [EnvironmentBuilder.glow(Palette.gold)])
                    let tip = ModelEntity(mesh: .generateBox(size: [0.08, 0.006, 0.08], cornerRadius: 0.003), materials: [EnvironmentBuilder.glow(Palette.gold)])
                    tip.position = [0, 0, -0.09]; tip.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
                    arrow.addChild(shaft); arrow.addChild(tip)
                    arrow.position = [0, 0.06, 0]
                    arrow.orientation = simd_quatf(angle: -yaw, axis: [0, 1, 0])
                    let worldArrow = Entity(); worldArrow.position = holder.position; worldArrow.addChild(arrow)
                    self.root.addChild(worldArrow)
                }
                self.root.addChild(holder)
                self.stones.append((holder, SIMD2<Float>(p.x, p.z)))
            }
            // far bank goal: lotus
            let loadedLotus = try? await Entity(named: "Lotus", in: .main)
            if let lotus = loadedLotus {
                let end = c + f * (self.spacing * Float(self.stoneCount + 1) + 0.45)
                lotus.position = [end.x, 0.01, end.z]
                lotus.scale = [1.4, 1.4, 1.4]
                self.goal = lotus
                self.root.addChild(lotus)
            }
            self.highlight(0)
        }
    }

    private func highlight(_ i: Int) {
        for (k, s) in stones.enumerated() {
            s.entity.children.first(where: { $0.name == "Glow" })?.removeFromParent()
            if k == i, let ring = EnvironmentBuilder.annulus(inner: 0.20, outer: 0.235) {
                let g = ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.9)])
                g.name = "Glow"; g.position.y = 0.05
                s.entity.addChild(g)
            }
        }
    }

    private func land(on i: Int, time: Double) {
        index = i + 1
        score += 1
        SoundManager.shared.playSpatial("sfx_stone", on: stones[i].entity)
        sparkles.burst(at: stones[i].entity.position + [0, 0.06, 0], color: Palette.mint, count: 12, speed: 0.6)
        feedback = config.hops ? (twoFoot ? "Soft two-foot landing" : "Land… and stick it") : ["Nice step", "Settle… good", "Steady"].randomElement()
        landedAt = time
        landingSway.reset()
        if index >= stones.count {
            feedback = "You crossed the river!"
            SoundManager.shared.play("sfx_levelup", volume: 0.8)
            sparkles.burst(at: goal.position + [0, 0.15, 0], color: Palette.gold, count: 30, speed: 1.0)
            returning = true
            highlight(-1)
        } else {
            highlight(index)
        }
    }

    func update(dt: Float, time: Double, tracker: MotionTracker) {
        sparkles.update(dt: dt)
        guard !stones.isEmpty else { return }
        let here = SIMD2<Float>(tracker.head.x, tracker.head.z)
        if returning {
            if simd_distance(here, startCentre) < 0.3 {
                rounds += 1
                feedback = "Round complete!"
                finished = true
            }
            return
        }
        // landing steadiness (stick the landing)
        if let t = landedAt {
            landingSway.add(tracker.head)
            if time - t > 1.3 {
                if landingSway.rmsMM < 14 { feedback = "Steady landing!"; score += 1; SoundManager.shared.play("sfx_success", volume: 0.5) }
                landedAt = nil
            }
        }
        let target = stones[index].centre
        if config.hops {
            if let ev = hop.add(head: tracker.head, velocityY: tracker.headVelocity.y), case .landing(let p) = ev {
                if simd_distance(p, target) < 0.32 {
                    let i = index
                    land(on: index, time: time)
                    if quarterTurns, i < targetYaw.count {
                        let f = tracker.headForward
                        var d = atan2(f.x, -f.z) - targetYaw[i]
                        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                        if abs(d) < 0.7 { score += 1; feedback = "Quarter turn, nicely controlled!" }
                        else { feedback = "Land facing the arrow next time" }
                    }
                } else if index > 0 && simd_distance(p, stones[index - 1].centre) < 0.2 {
                    // small re-balance hop on the same stone — ignore
                } else {
                    feedback = "Splash! Hop back to the last stone and try again"
                    SoundManager.shared.play("sfx_splash", volume: 0.7)
                }
            }
        } else {
            if simd_distance(here, target) < 0.2 {
                dwell += dt
                if dwell > 0.6 { dwell = 0; land(on: index, time: time) }
            } else { dwell = 0 }
        }
    }

    /// The next stone to step to, or the start ring on the way back.
    var guidePoint: SIMD3<Float>? {
        if returning { return [startCentre.x, 0, startCentre.y] }
        guard stones.indices.contains(index) else { return nil }
        let c = stones[index].centre
        return [c.x, 0, c.y]
    }

    func handleTap(_ entity: Entity) -> Bool { false }
    func stop() { finished = true; sparkles.clear(); root.removeFromParent() }
}
