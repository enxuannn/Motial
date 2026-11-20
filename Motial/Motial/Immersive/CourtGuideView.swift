import SwiftUI
import RealityKit
import AVFoundation

/// Court Smarts on Sunset Court. Three things only, so nothing competes for attention:
///  1. a curved cinema screen with real players doing the move,
///  2. a life-size 3D ankle beside it that rolls and points exactly as the move does, with the two ligaments a
///     sprain tears (ATFL, CFL) turning from green to red as they stretch,
///  3. one card: the verdict, why (in ankle terms), what to do instead, and what it means for you today.
struct CourtGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var guide = CourtGuideScene(sport: AppModel.shared.guideSport)
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content, attachments in
            content.add(guide.root)
            if let card = attachments.entity(for: "card") {
                card.position = [0, 0.82, -1.35]
                card.orientation = simd_quatf(angle: -0.38, axis: [1, 0, 0])
                guide.root.addChild(card)
                guide.card = card
            }
            subscription = content.subscribe(to: SceneEvents.Update.self) { e in guide.tick(Float(e.deltaTime)) }
            Task { @MainActor in await guide.build() }
        } attachments: {
            Attachment(id: "card") {
                CourtGuideCard(guide: guide, profile: model.profile, stage: model.stage) {
                    Task { await dismissImmersiveSpace() }
                }
            }
        }
        .onDisappear {
            subscription?.cancel()
            guide.stop()
            model.immersiveOpen = false
            if !model.mainWindowOpen { openWindow(id: "main") }
        }
    }
}

// MARK: - Card (the only UI)

struct CourtGuideCard: View {
    @Bindable var guide: CourtGuideScene
    let profile: PatientProfile?
    let stage: RehabStage
    var close: () -> Void

    var body: some View {
        let m = guide.move
        let you = CourtGuide.forYou(m, profile: profile, stage: stage)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                verdictChip(m.verdict)
                Spacer()
                Text("\(guide.index + 1) of \(guide.moves.count)").font(.headline).foregroundStyle(.secondary)
            }
            Text(m.title).font(.system(size: 40, weight: .bold))
            if !m.scenes180.isEmpty {
                HStack(spacing: 10) {
                    Label(guide.live ? "Live 3D · walk around" : "180° on court",
                          systemImage: guide.live ? "figure.walk.motion" : "pano.fill")
                        .font(.headline).foregroundStyle(.secondary)
                    ForEach(Array(m.scenes180.enumerated()), id: \.offset) { i, c in
                        Button { guide.pick180(i) } label: { Text(c.label).padding(.horizontal, 6) }
                            .buttonStyle(.bordered)
                            .tint(guide.clip180 == i ? Theme.accent : .secondary)
                    }
                }
            }
            Label(m.why, systemImage: "figure.walk.motion").font(.title2)
                .fixedSize(horizontal: false, vertical: true)
            Label(m.instead, systemImage: "checkmark.seal.fill").font(.title2)
                .foregroundStyle(Color(red: 0.55, green: 0.9, blue: 0.75))
                .fixedSize(horizontal: false, vertical: true)
            Label(you.text, systemImage: you.open ? "person.fill.checkmark" : "lock.fill")
                .font(.headline).foregroundStyle(you.open ? .green : .orange)
            Label("Source: " + m.evidence.compactMap { EvidenceLibrary.byID($0)?.shortCite }.joined(separator: "; "),
                  systemImage: "text.book.closed")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button { guide.go(-1) } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(guide.index == 0)
                Button { guide.replay() } label: { Label("Replay", systemImage: "gobackward") }
                Spacer()
                if guide.index < guide.moves.count - 1 {
                    Button { guide.go(1) } label: { Label("Next move", systemImage: "chevron.right").padding(.horizontal, 10) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                } else {
                    Button(action: close) { Label("Done", systemImage: "checkmark").padding(.horizontal, 10) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                Button(action: close) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 1000)
        .glassBackgroundEffect()
        .animation(.smooth, value: guide.index)
    }

    private func verdictChip(_ v: CourtMove.Verdict) -> some View {
        let (text, symbol, color): (String, String, Color) = switch v {
        case .safe: ("Safe while healing", "checkmark.circle.fill", .green)
        case .care: ("With care", "exclamationmark.triangle.fill", .yellow)
        case .notYet: ("Not yet", "hand.raised.fill", .red)
        }
        return Label(text, systemImage: symbol)
            .font(.title3.bold())
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Scene

@MainActor
@Observable
final class CourtGuideScene {
    let sport: PlaySport
    let moves: [CourtMove]
    init(sport: PlaySport) { self.sport = sport; self.moves = CourtGuide.moves(for: sport) }
    private(set) var index = 0
    private(set) var clip180 = 0
    /// true while a court scene plays as live 3D (real depth, walk around it) instead of the 180° video.
    private(set) var live = false
    var move: CourtMove { moves[index] }

    @ObservationIgnored let root = Entity()
    @ObservationIgnored var card: Entity?
    @ObservationIgnored private let screen = ModelEntity()
    @ObservationIgnored private let bezel = ModelEntity()
    // live 3D replay (Court3D.usdz): Maya and Alex life-size on the court
    @ObservationIgnored private let court3DRoot = Entity()
    @ObservationIgnored private var court3D: Entity?
    @ObservationIgnored private var liveClip: Clip180?
    @ObservationIgnored private var liveT: Float = 0
    @ObservationIgnored private let stage = Entity()          // court + cinema screen
    @ObservationIgnored private let dome = ModelEntity()      // 180° video around the viewer
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private let sharedPlayer: AVQueuePlayer = { let p = AVQueuePlayer(); p.isMuted = true; return p }()
    @ObservationIgnored private var screenHasVideo = false
    @ObservationIgnored private var domeHasVideo = false
    @ObservationIgnored private let ankle = ExplainAnkle()
    @ObservationIgnored private var t: Float = 0

    static let screenRadius: Float = 3.2
    static let screenCentreY: Float = 1.72

    func build() async {
        root.addChild(stage)
        stage.addChild(SportLabController.makeCourt(withModel: false))   // sky, ground and light; the court is in Court3D
        // 180° dome: rendered at the viewer's eye height, centred straight ahead
        if let mesh = Self.dome180(radius: 12) {
            dome.model = ModelComponent(mesh: mesh, materials: [EnvironmentBuilder.glow(.black)])
            dome.position = [0, 1.45, 0]
            dome.isEnabled = false
            root.addChild(dome)
        }
        // curved cinema screen with a soft dark bezel
        if let mesh = Self.curvedScreen(radius: Self.screenRadius + 0.03, arcDegrees: 49.5, height: 1.5, centreY: Self.screenCentreY) {
            bezel.model = ModelComponent(mesh: mesh, materials: [EnvironmentBuilder.glow(UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1), opacity: 0.85)])
            stage.addChild(bezel)
        }
        // The court scenes as live 3D: the viewer stands where the 180° camera stood (front-right of Maya, seeing the
        // outside of her right ankle), a little further back so there is room to step around them.
        court3DRoot.position = [0.25, 0, -1.6]
        court3DRoot.isEnabled = false
        root.addChild(court3DRoot)
        if moves.contains(where: { $0.scenes180.contains { $0.frames != nil } }) {   // only sports that have a 3D scene
            Task { @MainActor in await self.loadCourt3D() }
        }
        if let mesh = Self.curvedScreen(radius: Self.screenRadius, arcDegrees: 47, height: 1.42, centreY: Self.screenCentreY) {
            screen.model = ModelComponent(mesh: mesh, materials: [EnvironmentBuilder.glow(.black)])
            stage.addChild(screen)
        }
        ankle.root.position = [0.98, 1.22, -1.6]                                 // right of the card, below the screen edge
        ankle.root.orientation = simd_quatf(angle: -atan2(0.98, 1.6), axis: [0, 1, 0])   // face the viewer
        root.addChild(ankle.root)
        await ankle.load(height: 0.36)
        SoundManager.shared.stopAmbience()
        SoundManager.shared.say(sport.welcome)
        show()
    }

    func go(_ d: Int) {
        index = max(0, min(moves.count - 1, index + d))
        clip180 = 0
        show()
    }

    func pick180(_ i: Int) {
        clip180 = i
        show()
    }

    /// The 180° scene for this move, if it has one and the video is in the app.
    private var current180: Clip180? {
        guard move.scenes180.indices.contains(clip180) else { return nil }
        let c = move.scenes180[clip180]
        return Bundle.main.url(forResource: c.video, withExtension: "mp4") != nil ? c : nil
    }

    func replay() {
        player?.seek(to: .zero); player?.play()
        if live, let c = liveClip { startLive(c) }
        SoundManager.shared.say(narration, interrupt: true)
    }

    private var narration: String { current180?.line ?? "\(move.title). \(move.why)" }

    private func show() {
        applyMode()
        SoundManager.shared.say(narration, interrupt: true)
        SoundManager.shared.play("sfx_shimmer", volume: 0.3)
    }

    /// Chooses what plays: real footage on the cinema screen, a court scene as live 3D (preferred), or the
    /// 180° video dome when the 3D scene is not available.
    private func applyMode() {
        let c180 = current180
        let live3D = c180?.frames != nil && court3D != nil
        live = live3D
        dome.isEnabled = c180 != nil && !live3D
        stage.isEnabled = c180 == nil || live3D
        screen.isEnabled = !live3D
        bezel.isEnabled = !live3D
        // The 3D court stays as the setting for every scene on the court; the players and ball only in live 3D.
        court3DRoot.isEnabled = court3D != nil && (stage.isEnabled || live3D)
        // live scenes put you where the camera stood; as a backdrop for the screen the court sits further back,
        // so the hoop is ahead of you (not overhead) and nothing crosses the screen
        court3DRoot.position = live3D ? [0.25, 0, -1.6] : [0.25, 0, -5.2]
        for name in ["CoachRig", "CoachRig_001", "Ball"] { court3D?.findEntity(named: name)?.isEnabled = live3D }
        liveClip = live3D ? c180 : nil
        if live3D, let c = c180 { startLive(c) }
        // 180° and 3D scenes fill the centre, so the card steps aside to the left (the ankle panel is on the right)
        if let c = card {
            var tf = c.transform
            if c180 != nil {
                tf.translation = [-1.0, 1.05, -1.2]
                tf.rotation = simd_quatf(angle: atan2(1.0, 1.2), axis: [0, 1, 0]) * simd_quatf(angle: -0.12, axis: [1, 0, 0])
            } else {
                tf.translation = [0, 0.82, -1.35]
                tf.rotation = simd_quatf(angle: -0.38, axis: [1, 0, 0])
            }
            c.move(to: tf, relativeTo: c.parent, duration: 0.45, timingFunction: .easeInOut)
        }
        if live3D {
            player?.pause()
            looper?.disableLooping(); looper = nil
        } else if let u = Bundle.main.url(forResource: c180?.video ?? move.video, withExtension: "mp4") {
            // One player and one video material for the whole visit: switching moves swaps the clip in place.
            // (Creating a new VideoMaterial for every move left the screen black after the first one.)
            let p = sharedPlayer
            looper?.disableLooping(); looper = nil
            p.removeAllItems()
            looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: u))
            if c180 != nil {
                if !domeHasVideo { dome.model?.materials = [VideoMaterial(avPlayer: p)]; domeHasVideo = true }
            } else {
                if !screenHasVideo { screen.model?.materials = [VideoMaterial(avPlayer: p)]; screenHasVideo = true }
            }
            p.play()
            player = p
        }
        if let c = c180, c.video.hasSuffix("safe") {
            ankle.pose(plantar: 0.35, inversion: 0.02)        // a safe two-foot landing: the ankle stays upright
        } else {
            ankle.pose(plantar: move.plantar, inversion: move.inversion)
        }
    }

    func tick(_ dt: Float) {
        t += dt
        ankle.update(dt: dt)
        if live { updateLive(dt: dt) }
    }

    // MARK: Live 3D court scenes

    static let court3DFPS: Double = 24
    private enum Slot { case skin, bone, glow }
    /// Maya's model parts with their original materials and what each material slot is (RealityKit can merge the
    /// skin, bone and glow meshes of a skinned character into one model, so x-ray works per material slot).
    @ObservationIgnored private var mayaParts: [(e: ModelEntity, orig: [any RealityKit.Material], kinds: [Slot])] = []
    @ObservationIgnored private var animated: [Entity] = []
    @ObservationIgnored private var shownXray: Int = -1

    /// Loads Court3D.usdz once (both scenes on one timeline) and colours the props.
    private func loadCourt3D() async {
        guard court3D == nil, let e = try? await Entity(named: "Court3D", in: .main) else { return }
        court3D = e
        court3DRoot.addChild(e)
        Self.paintProps(e)
        addCourtLights()
        // the entities that carry animation; stop at the first level that has one, so nothing is driven twice
        func findAnimated(_ x: Entity) {
            if !x.availableAnimations.isEmpty { animated.append(x); return }
            x.children.forEach { findAnimated($0) }
        }
        findAnimated(e)
        if let maya = e.findEntity(named: "CoachRig") {
            for m in Self.models(in: maya) {
                let orig = m.model?.materials ?? []
                mayaParts.append((m, orig, orig.map(Self.slot(of:))))
            }
        }
        #if DEBUG
        print("[Motial] court3D: animated=\(animated.map(\.name)) maya parts=\(mayaParts.map { "\($0.e.name):\($0.kinds)" })")
        #endif
        setXray(0, sprain: true)
        if current180 != nil { applyMode() }     // a scene was already chosen while this loaded
    }

    /// Sunset key light plus two floodlight-style spotlights over the players, so the court and both people are lit
    /// the same way (positions in court3DRoot space: the players stand near the origin, the hoop to the left).
    private func addCourtLights() {
        let warm = UIColor(red: 1.0, green: 0.86, blue: 0.7, alpha: 1)
        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: warm, intensity: 5200))
        sun.look(at: [0, 0, -1], from: [4, 7, 3], relativeTo: nil)
        court3DRoot.addChild(sun)
        for (pos, target, lumens) in [(SIMD3<Float>(2.5, 6.5, 2.5), SIMD3<Float>(-0.2, 0.9, -0.3), Float(320_000)),
                                      (SIMD3<Float>(-4.5, 6.5, -2.0), SIMD3<Float>(-0.6, 0.6, -0.5), Float(240_000)),
                                      (SIMD3<Float>(0.3, 3.0, 3.0), SIMD3<Float>(-0.4, 1.0, -0.4), Float(200_000))] {
            let s = Entity()
            s.components.set(SpotLightComponent(color: UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), intensity: lumens,
                                                innerAngleInDegrees: 35, outerAngleInDegrees: 70, attenuationRadius: 25))
            s.look(at: target, from: pos, relativeTo: nil)
            court3DRoot.addChild(s)
        }
    }

    /// Starts the chosen scene as a repeating clip, trimmed out of the shared timeline.
    private func startLive(_ c: Clip180) {
        guard let fr = c.frames else { return }
        liveT = 0
        shownXray = -1
        for x in animated {
            guard let base = x.availableAnimations.first else { continue }
            var def = base.definition
            def.trimStart = Double(fr.lowerBound) / Self.court3DFPS
            def.trimEnd = Double(fr.upperBound) / Self.court3DFPS
            def.repeatMode = .repeat
            if let r = try? AnimationResource.generate(with: def) {
                x.playAnimation(r, transitionDuration: 0, startsPaused: false)
            }
        }
    }

    /// Fades in the x-ray view and the ligament glow on the same schedule as the rendered 180° clips
    /// (Tools/AssetPipeline/vr180.py, plan()), following the clip's own loop.
    private func updateLive(dt: Float) {
        guard let c = liveClip, let fr = c.frames else { return }
        liveT += dt
        let dur = Float(fr.count - 1) / Float(Self.court3DFPS)
        let local = liveT.truncatingRemainder(dividingBy: dur)
        var xr: Float = local > 2.1 ? min(1, (local - 2.1) / 0.7) : 0
        if local > 5.6 { xr = max(0, 1 - (local - 5.6) / 0.8) }
        setXray(xr, sprain: c.video.hasSuffix("sprain"), pulse: 0.75 + 0.25 * sin(t * 9))
    }

    private func setXray(_ xr: Float, sprain: Bool, pulse: Float = 1) {
        // materials change only in 10 % steps (and the glow pulse in 5 steps), not every frame
        let key = Int((xr * 10).rounded()) * 10 + (xr > 0.02 ? Int(((pulse - 0.5) * 8).rounded()) : 0)
        guard key != shownXray else { return }
        shownXray = key
        let on = xr > 0.02
        let colour = sprain ? UIColor(red: 1, green: 0.18, blue: 0.12, alpha: 1) : UIColor(red: 0.25, green: 1, blue: 0.55, alpha: 1)
        for part in mayaParts {
            var out: [any RealityKit.Material] = []
            for (i, k) in part.kinds.enumerated() where i < part.orig.count {
                switch k {
                case .skin:
                    // the same see-through teal skin as the coach's X-ray everywhere else in Motial
                    if on {
                        var m = PhysicallyBasedMaterial()
                        m.baseColor = .init(tint: UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 1))
                        m.roughness = .init(floatLiteral: 0.3)
                        m.faceCulling = .none
                        m.blending = .transparent(opacity: .init(floatLiteral: max(0.22, 1 - 0.78 * xr)))
                        out.append(m)
                    } else { out.append(part.orig[i]) }
                case .bone:
                    if on { out.append(part.orig[i]) } else {
                        var m = UnlitMaterial(color: .white); m.blending = .transparent(opacity: .init(floatLiteral: 0)); out.append(m)
                    }
                case .glow:
                    var m = UnlitMaterial(color: colour)
                    m.blending = .transparent(opacity: .init(floatLiteral: on ? min(1, 0.9 * xr * pulse) : 0))
                    out.append(m)
                }
            }
            part.e.model?.materials = out
        }
        // if the glow markers came through as their own models: the left one only lights up for the safe landing
        if let l = court3D?.findEntity(named: "InjuryGlow_L") { l.isEnabled = !sprain }
    }

    private static func slot(of mat: any RealityKit.Material) -> Slot {
        guard let p = mat as? PhysicallyBasedMaterial, p.baseColor.texture == nil else { return .skin }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        p.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        if r > 0.7 && r - g > 0.25 && r - b > 0.2 { return .glow }   // InjuryGlow
        if r > 0.7 && g > 0.65 && b > 0.55 { return .bone }          // Bone
        return .skin
    }

    private static func models(in e: Entity) -> [ModelEntity] {
        var out: [ModelEntity] = []
        if let m = e as? ModelEntity { out.append(m) }
        for c in e.children { out += models(in: c) }
        return out
    }

    /// Blender's procedural colours don't survive USD export, so the ball and hoop are coloured here.
    private static func paintProps(_ e: Entity) {
        var leather = PhysicallyBasedMaterial()
        leather.baseColor = .init(tint: UIColor(red: 0.85, green: 0.34, blue: 0.1, alpha: 1))
        leather.roughness = .init(floatLiteral: 0.7)
        let rim = SimpleMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1), isMetallic: true)
        let dark = SimpleMaterial(color: UIColor(red: 0.16, green: 0.18, blue: 0.27, alpha: 1), isMetallic: true)
        let white = UnlitMaterial(color: UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1))
        var net = UnlitMaterial(color: .white); net.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white); glass.roughness = .init(floatLiteral: 0.05)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        func walk(_ x: Entity) {
            let n = x.name
            if n == "Ball" { _ = leather }      // the textured basketball model keeps its own look
            else if n == "Torus" { paint(x, rim) }
            else if n == "Cone" { paint(x, net) }
            else if n == "Board" { paint(x, glass) }
            else if n == "Pole" || n == "Arm" { paint(x, dark) }
            else if n.hasPrefix("Frame") { paint(x, white) }
            else { x.children.forEach { walk($0) } }
        }
        walk(e)
    }

    private static func paint(_ e: Entity, _ m: any RealityKit.Material) {
        if let me = e as? ModelEntity, let k = me.model?.materials.count { me.model?.materials = Array(repeating: m, count: max(1, k)) }
        e.children.forEach { paint($0, m) }
    }

    func stop() {
        player?.pause()
        looper = nil
        SoundManager.shared.stopVoice()
    }

    /// Half sphere in front of the viewer for 180° equirectangular video (u: left → right, v: bottom → top).
    static func dome180(radius r: Float, lonSteps: Int = 96, latSteps: Int = 64) -> MeshResource? {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for i in 0...latSteps {
            let v = Float(i) / Float(latSteps)
            let lat = (v - 0.5) * .pi
            for j in 0...lonSteps {
                let u = Float(j) / Float(lonSteps)
                let lon = (u - 0.5) * .pi
                let d = SIMD3<Float>(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat))
                pos.append(d * r); nrm.append(-d); uv.append([u, v])
            }
        }
        let w = UInt32(lonSteps + 1)
        for i in 0..<UInt32(latSteps) {
            for j in 0..<UInt32(lonSteps) {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                idx += [a, b, c, b, d, c, a, c, b, b, c, d]
            }
        }
        var md = MeshDescriptor(name: "dome180")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(nrm)
        md.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        md.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [md])
    }

    /// A cylindrical cinema screen around the viewer (centre straight ahead), UVs filling the whole video.
    static func curvedScreen(radius r: Float, arcDegrees: Float, height h: Float, centreY: Float, segments: Int = 48) -> MeshResource? {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        let half = arcDegrees / 2 * .pi / 180
        for j in 0...segments {
            let u = Float(j) / Float(segments)
            let a = -half + 2 * half * u
            let x = r * sin(a), z = -r * cos(a)
            for (k, y) in [centreY - h / 2, centreY + h / 2].enumerated() {
                pos.append([x, y, z]); nrm.append(simd_normalize(SIMD3<Float>(-x, 0, -z)))
                uv.append([u, Float(k)])
            }
        }
        for j in 0..<UInt32(segments) {
            let a = j * 2, b = a + 1, c = a + 2, d = a + 3
            idx += [a, c, b, b, c, d, a, b, c, b, d, c]
        }
        var md = MeshDescriptor(name: "screen")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(nrm)
        md.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        md.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [md])
    }
}

// MARK: - The explaining ankle

/// The anatomy model seen from the outside of the ankle (where sprains happen). The foot rolls in (inversion) and
/// points down (plantarflexion) as much as the move asks of it; the ATFL and CFL are drawn between their real bone
/// attachments and glow green → yellow → red as they stretch.
@MainActor
final class ExplainAnkle {
    let root = Entity()
    private let model = Entity()
    private var foot: Entity?
    private var footBase = float4x4(1)          // the foot's own transform from the model file
    private var footParentInM = float4x4(1)     // foot's parent, expressed in the anatomy model's space
    private var anatomy: Entity?
    private var atfl = ModelEntity(), cfl = ModelEntity()
    private var readout = Entity()
    private var targetP: Float = 0, targetI: Float = 0
    private var cycle: Float = 0
    private var shownStrain = -1

    // model space (metres in AnkleAnatomy.usdz), measured from the bones
    private static let pivot = SIMD3<Float>(0.016, 0.045, -0.075)     // ankle axis, between the malleoli
    private static let fibulaTip = SIMD3<Float>(-0.009, 0.05, -0.064)  // lateral malleolus
    private static let talusNeck = SIMD3<Float>(0.004, 0.053, -0.035)  // ATFL attachment on the talus
    private static let calcLat = SIMD3<Float>(-0.007, 0.024, -0.082)   // CFL attachment on the calcaneus

    func load(height: Float) async {
        let card = ModelEntity(mesh: .generatePlane(width: 0.62, height: 0.74, cornerRadius: 0.06),
                               materials: [EnvironmentBuilder.glow(UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1), opacity: 0.6)])
        card.position = [0, 0, -0.16]
        root.addChild(card)
        let title = LiveAnkle.text("Inside your ankle", size: 0.034, color: .white)
        let tb = title.visualBounds(relativeTo: nil)
        title.position = [-tb.center.x, 0.29, -0.14]
        root.addChild(title)
        root.addChild(model)
        root.addChild(readout)
        guard let m = try? await Entity(named: "AnkleAnatomy", in: .main) else { return }
        let holder = Entity()
        holder.addChild(m)
        let b = m.visualBounds(relativeTo: holder)
        let s = height / max(b.extents.y, 0.001)
        holder.scale = [s, s, s]
        m.position = -b.center + [0, -0.03 / s, 0]
        // show the outer (lateral, −X) side to the viewer, turned a little to see the front of the ankle
        model.orientation = simd_quatf(angle: .pi / 2 - 0.35, axis: [0, 1, 0])
        model.addChild(holder)
        anatomy = m
        foot = m.findEntity(named: "Foot")
        if let f = foot {
            footBase = f.transform.matrix
            if let par = f.parent { footParentInM = par.transformMatrix(relativeTo: m) }
        }
        for (lig, name) in [(atfl, "ATFL"), (cfl, "CFL")] {
            lig.name = name
            m.addChild(lig)
        }
        let legend = LiveAnkle.text("ATFL + CFL: the ligaments a sprain stretches", size: 0.017, color: UIColor(white: 0.8, alpha: 1))
        let lb = legend.visualBounds(relativeTo: nil)
        legend.position = [-lb.center.x, -0.33, -0.14]
        root.addChild(legend)
        update(dt: 0)
    }

    func pose(plantar: Float, inversion: Float) {
        targetP = plantar; targetI = inversion
        cycle = 0
    }

    func update(dt: Float) {
        cycle += dt
        // move in, hold, return, rest: a calm ~4 s loop
        let c = cycle.truncatingRemainder(dividingBy: 4)
        let k: Float = c < 1.2 ? Self.ease(c / 1.2) : (c < 2.2 ? 1 : (c < 3.4 ? 1 - Self.ease((c - 2.2) / 1.2) : 0))
        // toes down (plantarflexion) + rolling in (inversion) with the small inward twist that comes with it
        let q = simd_quatf(angle: 0.6 * targetP * k, axis: [1, 0, 0]) * simd_quatf(angle: 0.5 * targetI * k, axis: [0, 0, 1])
            * simd_quatf(angle: 0.35 * targetI * k, axis: [0, 1, 0])
        let p = Self.pivot
        // rotate about the ankle axis (model space), keeping the foot's own transform from the file
        var d = float4x4(q)
        d.columns.3 = SIMD4<Float>(p - q.act(p), 1)
        foot?.transform = Transform(matrix: footParentInM.inverse * d * footParentInM * footBase)
        // ligaments between their bone attachments; the foot ends move with the foot
        let a = Self.fibulaTip
        let b = p + q.act(Self.talusNeck - p)
        let c2 = p + q.act(Self.calcLat - p)
        let s1 = place(atfl, from: a, to: b, rest: simd_length(Self.talusNeck - a))
        let s2 = place(cfl, from: a, to: c2, rest: simd_length(Self.calcLat - a))
        let strain = Int((max(s1, s2) * 100).rounded())
        if strain != shownStrain {
            shownStrain = strain
            Array(readout.children).forEach { $0.removeFromParent() }
            let colour = strain < 8 ? UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1)
                : (strain < 18 ? Palette.gold : UIColor(red: 1, green: 0.42, blue: 0.4, alpha: 1))
            let words = strain < 8 ? "relaxed" : (strain < 18 ? "loaded" : "overstretched")
            let t = LiveAnkle.text("Ligament stretch \(strain)%: \(words)", size: 0.026, color: colour)
            let tb = t.visualBounds(relativeTo: nil)
            t.position = [-tb.center.x, 0.22, -0.13]          // right under the title, clear of the bones
            readout.addChild(t)
        }
    }

    /// Positions a ligament band between two points and colours it by stretch; returns the strain (0 = rest length).
    private func place(_ e: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>, rest: Float) -> Float {
        let d = b - a
        let len = simd_length(d)
        let strain = max(0, len / max(rest, 0.0001) - 1)
        if e.model == nil { e.model = ModelComponent(mesh: .generateBox(size: [0.0055, 1, 0.0055]), materials: []) }
        e.model?.materials = [EnvironmentBuilder.glow(Self.strainColour(strain))]
        e.scale = [1, len, 1]
        e.position = (a + b) / 2
        let up = SIMD3<Float>(0, 1, 0)
        let dir = simd_normalize(d)
        let axis = simd_cross(up, dir)
        let angle = acos(max(-1, min(1, simd_dot(up, dir))))
        e.orientation = simd_length(axis) > 1e-5 ? simd_quatf(angle: angle, axis: simd_normalize(axis)) : simd_quatf(angle: 0, axis: [0, 1, 0])
        return strain
    }

    private static func strainColour(_ s: Float) -> UIColor {
        let k = max(0, min(1, s / 0.28))
        let g = UIColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 1), y = Palette.gold, r = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0, br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
        }
        return k < 0.5 ? mix(g, y, CGFloat(k * 2)) : mix(y, r, CGFloat((k - 0.5) * 2))
    }

    private static func ease(_ x: Float) -> Float { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }
}
