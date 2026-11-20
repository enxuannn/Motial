import RealityKit
import UIKit
import Foundation

struct CoachClip: Codable {
    let id: String
    let exercise: String
    let side: String
    let phase: String
    let seated: Bool
    let start: Double
    let end: Double
}

struct CoachManifest: Codable {
    struct Stool: Codable { let seatHeight: Float; let z: Float; let radius: Float }
    /// Ball points for the set shot (coach-local metres) and the release time within the 2.6 s clip.
    struct Shot: Codable { let hold: [Float]; let release: [Float]; let releaseTime: Double; let length: Double }
    var shot: Shot? = nil
    /// Motion-library bone names → this model's joints (e.g. "Hand_R": "RightHand_019").
    var map: [String: String?]? = nil
    let fps: Double
    let clips: [CoachClip]
    let stool: Stool
    let height: Float
}

/// Life-size, photoreal 3D coach (Sketchfab CC BY models) driven by the clinical motion library,
/// with CT-derived ankle bones (BodyParts3D) fitted inside the legs for the "See the ankle" view.
@MainActor
final class CoachRig {
    private static var templates: [CoachModel: Entity] = [:]
    private static var manifests: [CoachModel: CoachManifest] = [:]

    static func manifest(for c: CoachModel) -> CoachManifest? {
        if let m = manifests[c] { return m }
        guard let u = Bundle.main.url(forResource: c.manifestName, withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode(CoachManifest.self, from: d) else { return nil }
        manifests[c] = m
        return m
    }
    var coach: CoachModel = .fitness
    var manifest: CoachManifest? { Self.manifest(for: coach) }

    let root = Entity()
    private(set) var model: Entity?
    private var animated: Entity?
    private var base: AnimationResource?
    private var cache: [String: AnimationResource] = [:]
    private var stool: ModelEntity?
    private var bodyParts: [ModelEntity] = []
    private var originalMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    private(set) var currentClip: String?
    var injured: AnkleSide = .right
    var mirror = true
    private(set) var xray = false

    static func preload(_ c: CoachModel = .fitness) async {
        guard templates[c] == nil else { return }
        templates[c] = try? await Entity(named: c.fileName, in: .main)
    }

    func load() async {
        await Self.preload(coach)
        guard let t = Self.templates[coach] else { return }
        let m = t.clone(recursive: true)
        model = m
        root.addChild(m)
        animated = Self.findAnimated(m)
        base = animated?.availableAnimations.first
        bodyParts = Self.models(in: m)
        for b in bodyParts {
            // RealityKit may merge the skinned skin, bone and glow meshes into one model, so identify each
            // material slot by its look, and render skin double-sided (some scanned faces point inward).
            let mats: [any RealityKit.Material] = (b.model?.materials ?? []).map { mat in
                guard var p = mat as? PhysicallyBasedMaterial else { return mat }
                p.faceCulling = .none
                return p
            }
            b.model?.materials = mats
            originalMaterials[ObjectIdentifier(b)] = mats
            slotKinds[ObjectIdentifier(b)] = mats.map(Self.kind(of:))
        }
        buildStool()
        setXray(false)
    }

    private static func findAnimated(_ e: Entity) -> Entity? {
        if !e.availableAnimations.isEmpty { return e }
        for c in e.children { if let f = findAnimated(c) { return f } }
        return nil
    }
    private static func models(in e: Entity) -> [ModelEntity] {
        var out: [ModelEntity] = []
        if let m = e as? ModelEntity { out.append(m) }
        for c in e.children { out += models(in: c) }
        return out
    }
    private func named(_ prefix: String) -> [ModelEntity] {
        bodyParts.filter { $0.name.hasPrefix(prefix) || ($0.parent?.name.hasPrefix(prefix) ?? false) }
    }

    private func buildStool() {
        guard let st = manifest?.stool else { return }
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1))
        mat.roughness = .init(floatLiteral: 0.7)
        let s = ModelEntity(mesh: .generateCylinder(height: st.seatHeight, radius: st.radius), materials: [mat])
        s.position = [0, st.seatHeight / 2, st.z]
        s.isEnabled = false
        root.addChild(s)
        stool = s
    }

    /// Side shown by the coach. Mirroring makes a face-to-face coach move the same side as the person sees in a mirror.
    private var clipSide: AnkleSide { mirror ? injured.opposite : injured }

    /// The clip the session asked for (talking temporarily replaces "idle" / "seated_idle" while the voice speaks).
    private(set) var requested: String?
    private var talking = false
    private var quietFor: Double = 0
    private var lastTick: Double = 0

    func play(exercise: String, transition: TimeInterval = 0.45, speed: Float = 1) {
        requested = exercise
        if talking, let t = talkClip(for: exercise) { start(t, transition: transition, speed: speed); return }
        talking = false
        start(exercise, transition: transition, speed: speed)
    }

    /// Plays the current clip again from its first frame (keeps a demonstration in step with a rep cycle).
    func restart() {
        guard let id = currentClip, let animated, let res = cache[id] else { return }
        _ = animated.playAnimation(res, transitionDuration: 0, startsPaused: false)
    }

    private func talkClip(for exercise: String) -> String? {
        let t = exercise == "idle" ? "talk" : (exercise == "seated_idle" ? "seated_talk" : nil)
        guard let t, manifest?.clips.contains(where: { $0.exercise == t }) == true else { return nil }
        return t
    }

    /// Lip sync: while the voice coach speaks and the coach is standing or sitting idle, she talks (jaw, head and
    /// hand gestures); a short pause between sentences doesn't make her stop.
    private func updateTalking(time: Double) {
        let dt = max(0, min(0.1, time - lastTick)); lastTick = time
        guard let req = requested, let t = talkClip(for: req) else { talking = false; return }
        let voice = SoundManager.shared.isVoicePlaying
        quietFor = voice ? 0 : quietFor + dt
        if voice && !talking { talking = true; start(t, transition: 0.35) }
        else if talking && quietFor > 0.6 { talking = false; start(req, transition: 0.45) }
    }

    private func start(_ exercise: String, transition: TimeInterval = 0.45, speed: Float = 1) {
        let id = "\(exercise)_\(clipSide.clipSuffix)"
        guard id != currentClip, let animated, let base,
              let clip = manifest?.clips.first(where: { $0.id == id }) else { return }
        currentClip = id
        stool?.isEnabled = clip.seated
        let res: AnimationResource
        if let r = cache[id] { res = r } else {
            var def = base.definition
            def.trimStart = clip.start
            def.trimEnd = clip.end
            def.repeatMode = .repeat
            guard let r = try? AnimationResource.generate(with: def) else { return }
            cache[id] = r; res = r
        }
        let ctrl = animated.playAnimation(res, transitionDuration: transition, startsPaused: false)
        ctrl.speed = speed
    }

    func isSeated(_ exercise: String) -> Bool {
        manifest?.clips.first { $0.exercise == exercise }?.seated ?? false
    }

    private enum SlotKind { case skin, bone, glow }
    private var slotKinds: [ObjectIdentifier: [SlotKind]] = [:]
    private static func kind(of mat: any RealityKit.Material) -> SlotKind {
        guard let p = mat as? PhysicallyBasedMaterial, p.baseColor.texture == nil else { return .skin }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        // colours may come back colour-space converted, so compare loosely
        if r > 0.7 && r - g > 0.25 && r - b > 0.2 { return .glow }   // InjuryGlow (1.0, 0.25, 0.30)
        if r > 0.7 && g > 0.65 && b > 0.55 { return .bone }          // Bone (0.93, 0.89, 0.80)
        return .skin
    }

    /// Applies x-ray per material slot (works whether or not RealityKit merged the meshes).
    private func applySlots(_ on: Bool) {
        for b in bodyParts {
            guard let kinds = slotKinds[ObjectIdentifier(b)], let orig = originalMaterials[ObjectIdentifier(b)],
                  kinds.contains(where: { $0 != .skin }) || on else { continue }
            var out: [any RealityKit.Material] = []
            for (i, k) in kinds.enumerated() where i < orig.count {
                switch k {
                case .bone:
                    if on { out.append(orig[i]) } else {
                        var m = UnlitMaterial(color: .white); m.blending = .transparent(opacity: .init(floatLiteral: 0)); out.append(m)
                    }
                case .glow:
                    var m = UnlitMaterial(color: UIColor(red: 1, green: 0.3, blue: 0.35, alpha: 1))
                    m.blending = .transparent(opacity: .init(floatLiteral: on ? 0.85 : 0))
                    out.append(m)
                case .skin:
                    if on {
                        var m = PhysicallyBasedMaterial()
                        m.baseColor = .init(tint: UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1))
                        m.roughness = .init(floatLiteral: 0.3)
                        m.faceCulling = .none
                        m.blending = .transparent(opacity: .init(floatLiteral: 0.22))
                        out.append(m)
                    } else { out.append(orig[i]) }
                }
            }
            b.model?.materials = out
        }
    }

    /// See-through skin with the ankle bones and the injured ligament region glowing.
    func setXray(_ on: Bool) {
        xray = on
        let showSide = clipSide.clipSuffix
        for e in named("Bones_") { e.isEnabled = on && e.name.hasSuffix(showSide) || (on && (e.parent?.name.hasSuffix(showSide) ?? false)) }
        for e in named("InjuryGlow_") {
            let mine = e.name.hasSuffix(showSide) || (e.parent?.name.hasSuffix(showSide) ?? false)
            e.isEnabled = mine && on
            var m = UnlitMaterial(color: UIColor(red: 1, green: 0.3, blue: 0.35, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: on ? 0.85 : 0.0))
            e.model?.materials = [m]
        }
        for b in named("Body") {
            if on {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1))
                m.roughness = .init(floatLiteral: 0.3)
                m.blending = .transparent(opacity: .init(floatLiteral: 0.22))
                b.model?.materials = Array(repeating: m, count: max(1, b.model?.materials.count ?? 1))
            } else if let orig = originalMaterials[ObjectIdentifier(b)] {
                b.model?.materials = orig
            }
        }
        applySlots(on)
    }

    func refreshSide() {
        let ex = currentClip.map { String($0.dropLast(2)) }
        currentClip = nil
        setXray(xray)
        if let ex { start(ex, transition: 0.2) }
    }

    // MARK: Live joint positions (the ball follows the coach's hands)

    private var skinned: ModelEntity? { bodyParts.first { !$0.jointNames.isEmpty } }
    private var jointIndex: [String: Int] = [:]

    /// World position of a skeleton joint, found by the end of its path (e.g. "RightHand_019"), computed from the
    /// animated joint transforms, so it follows whatever clip is playing.
    func jointWorldPosition(_ name: String) -> SIMD3<Float>? {
        guard let m = skinned else { return nil }
        let names = m.jointNames
        if jointIndex.isEmpty { for (i, n) in names.enumerated() { jointIndex[n] = i } }
        guard let i = names.firstIndex(where: { $0 == name || $0.hasSuffix("/" + name) }) else { return nil }
        let locals = m.jointTransforms
        let parts = names[i].split(separator: "/")
        var mtx = matrix_identity_float4x4
        for k in 1...parts.count {
            if let j = jointIndex[parts.prefix(k).joined(separator: "/")], j < locals.count { mtx = mtx * locals[j].matrix }
        }
        return m.convert(position: SIMD3<Float>(mtx.columns.3.x, mtx.columns.3.y, mtx.columns.3.z), to: nil)
    }

    /// Between the coach's two hands (where a held ball sits), in world space.
    func handsWorldPosition() -> SIMD3<Float>? {
        guard let rName = manifest?.map?["Hand_R"] ?? nil, let lName = manifest?.map?["Hand_L"] ?? nil,
              let r = jointWorldPosition(rName), let l = jointWorldPosition(lName) else { return nil }
        let fwd = root.orientation.act([0, 0, 1])          // the coach's front
        return (r + l) / 2 + fwd * 0.09 + [0, 0.03, 0]
    }

    /// Gentle pulse for the injury marker, and the talking animation.
    func tick(time: Double) {
        updateTalking(time: time)
        guard xray else { return }
        let s = Float(1 + 0.18 * sin(time * 3.2))
        for e in named("InjuryGlow_") where e.isEnabled { e.scale = [s, s, s] }
    }
}
