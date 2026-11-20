import RealityKit
import UIKit
import simd

/// Single-leg stance: a lotus opens while the person stays steady; fireflies rise when balance is calm.
@MainActor
final class BalanceBloomGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var status: String { "Calm balance \(Int(bloom * 100))%" }

    private let config: GameConfig
    private var lotus: Entity?
    private var petals: Entity?
    private var core: ModelEntity?
    private let sparkles = Sparkles()
    private var sway = SwayMeter()
    private var bloom: Float = 0
    private var steadyTime: Float = 0
    private var moteTimer: Float = 0
    private var milestones: Set<Int> = []

    init(config: GameConfig) { self.config = config }

    func start(tracker: MotionTracker) {
        root.addChild(sparkles.root)
        let anchor = Entity()
        anchor.position = tracker.centre + tracker.headForward * 1.15 + [0, 0.95, 0]
        root.addChild(anchor)
        // water disc
        if let disc = EnvironmentBuilder.annulus(inner: 0.0, outer: 0.32) {
            let w = ModelEntity(mesh: disc, materials: [EnvironmentBuilder.glow(Palette.water, opacity: 0.45)])
            w.position.y = -0.005
            anchor.addChild(w)
        }
        if let ring = EnvironmentBuilder.annulus(inner: 0.30, outer: 0.32) {
            anchor.addChild(ModelEntity(mesh: ring, materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.8)]))
        }
        Task { @MainActor in
            let loaded = try? await Entity(named: "Lotus", in: .main)
            if let l = loaded {
                l.scale = [1.6, 1.6, 1.6]
                anchor.addChild(l)
                self.lotus = l
                self.petals = l.findEntity(named: "LotusPetals")
                self.core = l.findEntity(named: "LotusCore") as? ModelEntity
                    ?? (l.findEntity(named: "LotusCore")?.children.first as? ModelEntity)
            }
        }
        sway.reset()
    }

    func update(dt: Float, time: Double, tracker: MotionTracker) {
        sway.add(tracker.head)
        let live = Float(sway.liveSteadiness)
        bloom += (live - bloom) * min(1, dt * 1.5)
        if live > 0.6 { steadyTime += dt }
        score = Int(steadyTime)
        if let petals {
            let s = 0.45 + 0.55 * bloom
            petals.scale = [s, 0.6 + 0.4 * bloom, s]
            petals.orientation = simd_quatf(angle: Float(time) * 0.15, axis: [0, 1, 0])
        }
        if let core {
            var m = UnlitMaterial(color: UIColor(red: 1, green: CGFloat(0.7 + 0.3 * bloom), blue: 0.35, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: 0.6 + 0.4 * bloom))
            core.model?.materials = [m]
        }
        moteTimer += dt
        if bloom > 0.55 && moteTimer > 0.18 {
            moteTimer = 0
            if let l = lotus { sparkles.drift(around: l.position(relativeTo: nil), color: bloom > 0.8 ? Palette.gold : Palette.mint, radius: 0.35) }
        }
        sparkles.update(dt: dt)
        for m in [10, 20, 30, 45] where score >= m && !milestones.contains(m) {
            milestones.insert(m)
            feedback = m >= 30 ? "\(m) steady seconds — superb!" : "\(m) steady seconds!"
            SoundManager.shared.play("sfx_success", volume: 0.7)
            if let l = lotus { sparkles.burst(at: l.position(relativeTo: nil) + [0, 0.1, 0], color: Palette.gold, count: 24, speed: 0.8) }
        }
    }

    var steadiness: Double { sway.score }
    var touchdowns: Int { sway.touchdowns }

    func handleTap(_ entity: Entity) -> Bool { false }
    func stop() { finished = true; sparkles.clear(); root.removeFromParent() }
}
