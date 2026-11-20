import RealityKit
import UIKit
import simd

/// Reads "how far the toes point down" (0 … 1) the same way for every pedal game:
/// standing = heel-raise height from head tracking (≈ 4–5 cm = full), seated = the Steady Shin iPhone on the foot,
/// no tracking (Simulator) = a calm demo rhythm. Also judges smoothness: low jerk, no bouncing, little sway.
@MainActor
struct AnklePedal {
    let seated: Bool
    private(set) var value: Float = 0
    private(set) var smooth: Float = 0.8
    private(set) var demo = false
    private(set) var jerkSpike = false
    private(set) var rises = 0
    /// + pressing (toes going down), − releasing, in pedal units per second
    private(set) var velocity: Float = 0
    /// true / false on the frame the phone connects / disconnects (seated only), else nil
    private(set) var connectionChanged: Bool?

    private var baseline: Float?
    private var lastY: Float?
    private var vy: Float = 0
    private var lastVy: Float = 0
    private var jerk: Float = 0
    private var counter = HeadRepCounter(direction: .up)
    private var t: Float = 0
    private var wasConnected = false
    private static let full: Float = 0.042      // metres of head rise (or phone-equivalent) for a full press

    init(seated: Bool) {
        self.seated = seated
        counter.threshold = 0.025
        if seated { ShinLink.shared.start() }
    }

    mutating func update(dt: Float, tracker: MotionTracker) {
        guard dt > 0 else { return }
        t += dt
        connectionChanged = nil
        if seated {
            let c = ShinLink.shared.connected
            if c != wasConnected {
                wasConnected = c
                connectionChanged = c
                lastY = nil; vy = 0; lastVy = 0; jerk = 0
            }
            demo = !c
        } else {
            demo = !tracker.running
        }

        let y: Float
        if seated && !demo {
            y = 1.6 + 0.05 * ShinLink.shared.value
        } else if demo {
            let ph = fmod(t, 5.0)                          // up 1.2 s, hold 0.6 s, lower 2.6 s, rest
            let s: Float = ph < 1.2 ? ph / 1.2 : (ph < 1.8 ? 1 : max(0, 1 - (ph - 1.8) / 2.6))
            y = 1.6 + 0.05 * s * s * (3 - 2 * s)
        } else {
            y = tracker.head.y
        }

        if seated && !demo {
            // the phone is already calibrated (0 resting … 1 full range): use it directly, a held press stays pressed
            baseline = 1.6
            value = ShinLink.shared.value
        } else {
            var b = baseline ?? y
            let l0 = y - b
            if l0 < 0 { b += l0 * min(1, dt * 2) }               // settled lower: follow quickly
            else if l0 < 0.012 { b += l0 * min(1, dt * 0.5) }    // slow posture drift while resting
            baseline = b
            value = max(0, min(1, (y - b - 0.008) / Self.full))
        }

        let rawV = lastY.map { (y - $0) / dt } ?? 0
        lastY = y
        vy += (rawV - vy) * min(1, dt * 10)
        let acc = (vy - lastVy) / dt
        lastVy = vy
        jerk += (abs(acc) - jerk) * min(1, dt * 3)
        velocity = vy / Self.full

        let horiz: Float = (demo || seated) ? 0 : simd_length(SIMD2<Float>(tracker.headVelocity.x, tracker.headVelocity.z))
        let calm = max(0, min(1, 1 - (jerk - 0.35) / 1.4))
        let still = max(0, min(1, 1 - (horiz - 0.12) / 0.25))
        let unhurried: Float = abs(vy) > 0.3 ? 0.3 : 1
        smooth += (calm * still * unhurried - smooth) * min(1, dt * 0.8)
        jerkSpike = !demo && (abs(acc) > 2.2 || abs(vy) > 0.32 || horiz > 0.35)

        counter.add(y)
        rises = counter.count
    }
}

/// "Your ankle, live": the anatomy model floating beside a pedal game. The foot bones tilt with the pedal,
/// the calf–Achilles glows gold while pushing (toes down), the tibialis anterior glows teal while lowering with
/// control, and the fibularis (peroneals) glow while balancing on the toes. A label names what is working.
@MainActor
final class LiveAnkle {
    let root = Entity()
    private let spin = Entity()
    private var foot: Entity?
    private var muscles: [String: ModelEntity] = [:]
    private var original: [String: [any RealityKit.Material]] = [:]
    private var lit: [String: Bool] = [:]
    private var label: ModelEntity?
    private var labelText = ""
    private var shown: Float = 0
    private var t: Float = 0
    /// Smoothed pedal level shown by the panel (0 resting … 1 toes down).
    var level: Float { shown }
    /// Plain-language learning tip for what is working now.
    private(set) var tip: String = LiveAnkle.tips["rest"]!
    private var spoken: Set<String> = []
    private var stateKey = "rest"
    private var stateTime: Float = 0

    static let tips: [String: String] = [
        "push": "Pushing: your calf and Achilles drive you forward, the same push-off you use to walk.",
        "control": "Easing off: your shin muscle is controlling the foot. Slow is strong.",
        "hold": "Holding: the peroneals on the outside of your ankle keep it from rolling.",
        "rest": "Resting: let the foot relax before the next press.",
    ]

    func load(height: Float = 0.4) async {
        let card = ModelEntity(mesh: .generatePlane(width: 0.6, height: 0.68, cornerRadius: 0.06),
                               materials: [EnvironmentBuilder.glow(UIColor(red: 0.05, green: 0.09, blue: 0.2, alpha: 1), opacity: 0.55)])
        card.position = [0, 0.0, -0.14]
        root.addChild(card)
        let title = Self.text("Your ankle, live", size: 0.03, color: .white)
        title.position = [-0.26, 0.27, -0.12]
        root.addChild(title)
        root.addChild(spin)
        guard let m = try? await Entity(named: "AnkleAnatomy", in: .main) else { return }
        let holder = Entity()
        holder.addChild(m)
        let b = m.visualBounds(relativeTo: holder)
        let s = height / max(b.extents.y, 0.001)
        holder.scale = [s, s, s]
        m.position = -b.center + [0, -0.02 / s, 0]
        spin.addChild(holder)
        foot = m.findEntity(named: "Foot")
        for n in ["achilles_tendon", "tibialis_anterior", "fibularis_longus", "fibularis_brevis"] {
            guard let e = m.findEntity(named: n) else { continue }
            if let me = (e as? ModelEntity) ?? (e.children.first as? ModelEntity) {
                muscles[n] = me
                original[n] = me.model?.materials ?? []
            }
        }
        setLabel("Resting")
    }

    /// value: 0 resting … 1 toes fully down; velocity: + pressing, − lowering (pedal units / s)
    func update(value: Float, velocity: Float, dt: Float) {
        t += dt
        shown += (value - shown) * min(1, dt * 12)
        foot?.orientation = simd_quatf(angle: 0.6 * shown, axis: [1, 0, 0])      // plantarflexion
        spin.orientation = simd_quatf(angle: .pi / 2 + sin(t * 0.35) * 0.35, axis: [0, 1, 0])
        let pushing = velocity > 0.25
        let controlling = velocity < -0.12 && shown > 0.04
        let holding = !pushing && !controlling && shown > 0.3
        glow("achilles_tendon", pushing || holding ? Palette.gold : nil)
        glow("tibialis_anterior", controlling ? Palette.teal : nil)
        glow("fibularis_longus", shown > 0.25 ? Palette.pink : nil)
        glow("fibularis_brevis", shown > 0.25 ? Palette.pink : nil)
        let key = pushing ? "push" : controlling ? "control" : holding ? "hold" : "rest"
        if key != stateKey { stateKey = key; stateTime = 0 } else { stateTime += dt }
        if stateTime > 0.6, let tp = Self.tips[key], tp != tip {
            tip = tp
            // each learning moment is spoken once per game (the pre-recorded human voice), never on rest
            if key != "rest" && !spoken.contains(key) && t > 4 {
                spoken.insert(key)
                SoundManager.shared.say(tp)
            }
        }
        setLabel(pushing ? "Calf + Achilles: pushing"
                 : controlling ? "Shin muscle: lowering with control"
                 : holding ? "Holding: peroneals keep you steady"
                 : "Resting")
    }

    private func glow(_ name: String, _ color: UIColor?) {
        guard let e = muscles[name] else { return }
        let on = color != nil
        if lit[name] == on && !on { return }
        lit[name] = on
        if let c = color {
            var m = UnlitMaterial(color: c)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.75 + 0.25 * sin(t * 6)))
            e.model?.materials = [m]
        } else if let o = original[name] {
            e.model?.materials = o
        }
    }

    private func setLabel(_ s: String) {
        guard s != labelText else { return }
        labelText = s
        label?.removeFromParent()
        let l = Self.text(s, size: 0.024, color: UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1))
        l.position = [-0.26, -0.3, -0.12]
        root.addChild(l)
        label = l
    }

    static func text(_ s: String, size: CGFloat, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(s, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: .semibold))
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
    }
}
