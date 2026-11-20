import RealityKit
import Metal
import ImageIO
import UIKit
import simd

/// Dawn Drive · Cockpit: a seated, first-person drive in an open roadster down a festive meadow road in full 360°.
/// Hot-air balloons drift in the sunrise, wind turbines turn on the fields, flowers line the road and bunting hangs
/// from the lantern gates. A real instrument cluster (speedometer, "toes down" dial, orbs, gates, time) sits on the dash.
/// Your foot is the accelerator (Motial Pedal iPhone on the foot: toes down = go, toes up slowly = ease off) and your
/// hands are on the wheel (hand tracking: tilt the wheel to change lanes and collect light orbs).
///
/// Clinical and comfort rules (Motial Clinical Evidence & Design Report §6; Apple HIG "Motion", visionOS):
/// • Seated only: 360° immersion is reserved for seated exercises; standing work never hides the real floor.
/// • Stationary frame of reference: the car (bonnet, dashboard, wheel, windscreen pillars) and the sky never move
///   relative to you; only the road and roadside pass by. The road is straight, so the world never rotates
///   (HIG: "avoid letting people rotate a virtual world"); steering changes lanes instead.
/// • Gentle, capped speed and acceleration, smooth by design: cybersickness rises with speed and exposure, so a run
///   is about a minute, top speed is a brisk cycling pace (lower with Reduce Motion), and the scene fades in and out.
/// • Low-contrast, sparse periphery (HIG: avoid motion at the edges of the field of view); no sustained ~0.2 Hz sway.
/// • The skill trained is ankle control: gold lantern gates ask you to ease off in time (slow, controlled release),
///   the same eccentric control as lowering a heel raise. Arms can rest at any time: lane assist takes over.
@MainActor
final class CockpitDriveGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    var stats: [GameStat] {
        [GameStat(value: "\(Int(progress * 100))%", label: "Course", progress: Double(progress)),
         GameStat(value: "\(orbsCollected)", label: "Orbs"),
         GameStat(value: "\(cleanGates)/\(gatesPassed)", label: "Smooth gates"),
         GameStat(value: GameRecordsCard.clock(Double(t)), label: "Time")]
    }
    var pedalLevel: Float? { pedal.value }
    var summary: GameSummary? {
        GameSummary(orbs: orbsCollected, cleared: cleanGates, total: gatesPassed, obstacleName: "gates",
                    bestLap: nil, smoothness: Double(smoothN > 0 ? smoothSum / smoothN : 0), completed: progress >= 1)
    }
    var learnTip: String? { anatomy.tip }
    var status: String { "\(Int(progress * 100))% · \(orbsCollected) orbs · \(cleanGates) of \(gatesPassed) gates smooth" }
    var hidesCoach: Bool { true }

    private let config: GameConfig
    private var pedal: AnklePedal
    private let stage = Entity()
    private let world = Entity()          // everything that streams past (road marks, roadside, orbs, gates)
    private let cockpit = Entity()        // fixed to the person: rest frame
    private let wheel = Entity()
    private let anatomy = LiveAnkle()
    private let sparkles = Sparkles()
    private let audio = DriveAudio(loudness: 1)
    private var smoothSum: Float = 0
    private var smoothN: Float = 0
    private let carBody = Entity()
    private let wheelProc = Entity()
    /// The scene stays hidden until the real car and wheel have loaded, so the person never sees the simple
    /// placeholder car swap into the real one (owner feedback 28 Oct: "the car keeps jumping between models").
    private var carReady = false
    private var waitClock: Float = 0
    private var heldHidden = false
    // instrument cluster
    private struct Dial { let needle: Entity; let ticks: [ModelEntity]; let accent: UIColor; let readout: Entity; var lit = -1; var shown = -1 }
    private let cluster = Entity()
    private var speedDial: Dial?
    private var ankleDial: Dial?
    private var centreText: Entity?
    private var centreKey = ""
    private let progressHolder = Entity()
    static let dialMaxKmh: Float = 20
    // festive scenery
    private var balloons: [(e: Entity, base: SIMD3<Float>, phase: Float)] = []
    private var rotors: [(e: Entity, axis: SIMD3<Float>, phase: Float)] = []
    private var ground: ModelEntity?
    private var groundMat: PhysicallyBasedMaterial?
    private var roadSurface: ModelEntity?
    private var roadMat: PhysicallyBasedMaterial?
    static let driverEye: Float = 1.11    // driver's seat of a small convertible: eyes about 1.1 m above the road
    static let flow: Float = -1           // texture scroll direction along the road
    private var fade: Float = 0
    private let veil = ModelEntity()
    private var ibl: Entity?

    private struct Thing { let e: Entity; var z: Float; let x: Float; let kind: Kind; var done = false; var t: Float = 0
        enum Kind { case dash, scenery, orb, gate, finish, fixed } }
    private var things: [Thing] = []

    private var eye: Float = 1.15
    private var speed: Float = 0
    private var distance: Float = 0
    private var carX: Float = 0           // lateral position of the car on the road (the world shifts the other way)
    private var steer: Float = 0
    private var handsOn = false
    private var t: Float = 0
    private var doneTimer: Float = 0
    private(set) var orbsCollected = 0
    private var gatesPassed = 0
    private var cleanGates = 0
    private var gateWarned = false
    private var wasHands = false
    // hand steering, measured in the car's own frame (never relative to where the head is turned)
    private var leftF: SIMD3<Float>?            // filtered hand positions, car frame
    private var rightF: SIMD3<Float>?
    private var handsSeen: Float = 0            // hysteresis: hands must be on the wheel briefly to take over…
    private var handsLost: Float = 0            // …and gone briefly before lane assist returns (no flicker on lost frames)
    private var footAssist = false              // no foot device: cruise assist holds a gentle speed and eases off for gates
    private var assistPedal: Float = 0
    private var footValue: Float = 0            // what drives the car: the pedal, or cruise assist
    private var shownInputs = ""
    private let inputsHUD = Entity()
    private var gateLanes: [Float: Float] = [:] // gate z → lane x the gate asks for (coordinated steer + ease-off)
    private let roadGroup = Entity()            // road surface and edge lines: shift with the car's lane like the kerbs
    private var paused = false
    // race start, ease-off guide, windscreen HUD, streaks
    private var startLamps: [ModelEntity] = []
    static let countdownLength: Float = 3.5
    private var countdown: Float = CockpitDriveGame.countdownLength
    private var guideBars: [ModelEntity] = []
    private var guideState = -1
    private let hud = Entity()
    private var shownHUD = ""
    private var hudAge: Float = 0
    private var streak = 0
    private var bestStreak = 0

    private var maxSpeed: Float { config.reduceMotion ? 3.0 : 5.0 }   // m/s (≈ 11–18 km/h)
    static let accel: Float = 1.2                                      // m/s² cap
    static let runLength: Float = 260                                  // metres ≈ 70–90 s
    static let gateSpeed: Float = 2.6
    static let laneX: [Float] = [-1.25, 0, 1.25]
    private var progress: Float { min(1, distance / Self.runLength) }

    init(config: GameConfig) {
        self.config = config
        self.pedal = AnklePedal(seated: true)
    }

    // MARK: Setup
    func start(tracker: MotionTracker) {
        // Sit the person in the driver's seat: the road is placed 1.1 m below their eyes.
        let realEye = max(0.95, min(1.8, tracker.head.y))     // seated or standing: the wheel always sits at the hands
        eye = Self.driverEye
        stage.position = [tracker.centre.x, realEye - Self.driverEye, tracker.centre.z]
        stage.orientation = yawToward(tracker.headForward)
        root.addChild(stage)
        root.addChild(sparkles.root)

        // Sunrise over open fields (Poly Haven "Bloem Field Sunrise", CC0, full 8K, cropped to the visible band from 30°
        // below the horizon up): a still 360° landscape, so the horizon never moves. A small full panorama of the same
        // photo lights the car, road and grass (image-based lighting), so they belong to the dawn.
        let skyName = Bundle.main.url(forResource: "env_drive_sky", withExtension: "jpg") != nil ? "env_drive_sky" : "env_dawn_sky"
        let cropped = skyName == "env_drive_sky"
        if let u = Bundle.main.url(forResource: skyName, withExtension: "jpg"),
           let tex = try? TextureResource.load(contentsOf: u),
           let dome = EnvironmentBuilder.patch(radius: 80, azSpan: 360, elMin: -30, elMax: 90, azSteps: 160, elSteps: 72,
                                               imageElMin: cropped ? -30 : -90) {
            var m = UnlitMaterial()
            m.color = .init(tint: .white, texture: .init(tex))
            let d = ModelEntity(mesh: dome, materials: [m])
            d.position.y = eye
            stage.addChild(d)
            let lightURL = Bundle.main.url(forResource: "env_drive_light", withExtension: "jpg") ?? u
            Task { @MainActor in await self.applyLighting(from: lightURL) }
        }
        // Grass and race-track asphalt (Poly Haven "Leafy Grass" and "Asphalt Track", CC0) that flow past as you drive.
        // The grass ends before the horizon so the photographed fields carry on beyond it.
        if let mat = Self.tiled(Bundle.main.url(forResource: "tex_leafy_grass", withExtension: "jpg") != nil ? "tex_leafy_grass" : "tex_grass",
                                scale: [36, 36]) {
            let g = ModelEntity(mesh: .generatePlane(width: 110, depth: 110), materials: [mat])
            g.position = [0, 0, -40]
            stage.addChild(g)
            ground = g; groundMat = mat
        }
        let roadMaterial = Self.tiled(Bundle.main.url(forResource: "tex_asphalt_track", withExtension: "jpg") != nil ? "tex_asphalt_track" : "tex_asphalt",
                                      scale: [1.5, 34]) ?? Self.matte(UIColor(red: 0.2, green: 0.21, blue: 0.25, alpha: 1))
        let road = ModelEntity(mesh: .generatePlane(width: 3.9, depth: 90), materials: [roadMaterial])
        road.position = [0, 0.02, -42]
        world.addChild(roadGroup)
        roadGroup.addChild(road)
        roadSurface = road; roadMat = roadMaterial
        for x: Float in [-1.92, 1.92] {
            let line = ModelEntity(mesh: .generatePlane(width: 0.08, depth: 90), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.8)])
            line.position = [x, 0.026, -42]
            roadGroup.addChild(line)
        }
        stage.addChild(world)
        spawnInitial()

        buildCockpit()
        stage.addChild(cockpit)
        Task { @MainActor in await self.loadTrees() }
        Task { @MainActor in await self.loadScenery() }
        Task { @MainActor in await self.loadCar() }
        addStartLights()
        addGuide()
        hud.position = [0, eye + 0.05, -1.1]               // just above the horizon, under the windscreen frame
        cockpit.addChild(hud)
        addFlowers()
        addFinish()

        // "Your ankle, live" sits on the dashboard (part of the still frame)
        anatomy.root.scale = [0.42, 0.42, 0.42]
        // over the passenger side of the dash (the driver sits on the right), clear of the session panel
        anatomy.root.position = [-0.95, eye + 0.02, -1.15]
        anatomy.root.look(at: [-1.9, eye + 0.02, -2.3], from: anatomy.root.position, relativeTo: stage)
        cockpit.addChild(anatomy.root)
        Task { @MainActor in await self.anatomy.load(height: 0.42) }

        // Fade in and out with a dark veil around the head instead of fading the whole scene: fading every part at
        // once made the road and grass see-through, so the photo behind showed through and the road looked like it
        // floated and moved on its own (owner feedback 28 Oct).
        var vm = UnlitMaterial(color: .black)
        vm.faceCulling = .none
        vm.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        veil.model = ModelComponent(mesh: .generateSphere(radius: 0.38), materials: [vm])
        veil.position = [0, eye, 0]
        stage.addChild(veil)
        audio.start(goCue: false)
        feedback = "Seated, back supported. Eyes on the horizon. Tap STOP any time"
        ShinLink.shared.sendStatus("Cockpit drive · ready")
    }

    /// A repeating texture (grass, asphalt) whose UV offset can be animated to show movement.
    private static func tiled(_ name: String, scale: SIMD2<Float>) -> PhysicallyBasedMaterial? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let tex = try? TextureResource.load(contentsOf: u) else { return nil }
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear
        d.maxAnisotropy = 8
        var m = PhysicallyBasedMaterial()
        // grass is tinted toward the sunrise field in the photo so the two meet softly at the horizon
        m.baseColor = .init(tint: name.contains("grass") ? UIColor(red: 0.86, green: 0.92, blue: 0.7, alpha: 1) : UIColor(white: 0.92, alpha: 1),
                            texture: .init(tex, sampler: .init(d)))
        m.roughness = .init(floatLiteral: 0.95)
        m.textureCoordinateTransform = .init(offset: .zero, scale: scale, rotation: 0)
        return m
    }

    /// Lights the scene with the sunrise panorama itself (image-based lighting) so the pearl car, road and grass
    /// pick up the warm dawn light and reflections.
    private func applyLighting(from url: URL) async {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let env = try? await EnvironmentResource(equirectangular: img) else { return }
        let light = Entity()
        light.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.6))
        stage.addChild(light)
        stage.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for e in [world, cockpit] { e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light)) }
        ibl = light
        if let g = ground { g.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light)) }
    }

    // MARK: The car: a real convertible interior
    /// "Cuy3" by paraje3d (Sketchfab, CC BY 4.0), a small unbadged convertible with a full interior, repainted in Motial
    /// pearl. The model came with an identical instrument pod in front of both seats; the one in front of the passenger
    /// seat was removed from the mesh (Tools/AssetPipeline/remove_passenger_pod.py), so there is one driver's seat
    /// (right-hand drive, as in Singapore) with the wheel and the Motial cluster in front of it. Its badge texture, stock
    /// gauge graphic and slogan number plates are replaced or hidden and the windscreen is made clear.
    /// The wheel is "Racing Steering Wheel - Game-Ready 3D Model" by GAMICO (Sketchfab, CC BY 4.0), without its desk clamp.
    private func loadCar() async {
        defer { carReady = true }
        var carLoaded = false, wheelLoaded = false
        defer {
            if !carLoaded { carBody.isEnabled = true }
            if !wheelLoaded { wheelProc.isEnabled = true }
        }
        if let car = try? await Entity(named: "RemerCar", in: .main) {
            let holder = Entity()
            let oriented = Entity()
            oriented.addChild(car)
            holder.addChild(oriented)
            let groups = car.findEntity(named: "Material2_1")?.parent
            func group(_ name: String) -> Entity? { groups?.children.first { $0.name == name } ?? car.findEntity(named: name) }
            // find the front of the car from its own parts: grille (front) and seats
            var flipped = false
            if let grille = group("Material2_12"), let seats = group("Material2_17"),
               grille.visualBounds(relativeTo: holder).center.z > seats.visualBounds(relativeTo: holder).center.z {
                oriented.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])          // nose toward −Z (forward)
                flipped = true
            }
            let b = holder.visualBounds(relativeTo: holder)
            if b.extents.x > 0.01, let gauges = group("Material2_25"), let seats = group("Material2_17") {
                let u = b.extents.x / 4.42                                   // the model's own unit
                let g = gauges.visualBounds(relativeTo: holder).center       // the driver's instrument pod
                let st = seats.visualBounds(relativeTo: holder).center
                // the person sits in the driver's seat: straight behind the remaining (driver's) pod
                // driver's seat: right-hand side (the pod there is kept; the passenger's pod was removed from the mesh)
                let driverX = b.center.x + (flipped ? -0.80 : 0.80) * u
                let eyeU = SIMD3<Float>(driverX, g.y + 0.63 * u, st.z + 0.155 * u)
                let sc = 1.11 / max(eyeU.y - b.min.y, 0.001)                  // eyes 1.11 m above the road, tyres on it
                oriented.scale = [sc, sc, sc]
                oriented.position = SIMD3<Float>(0, 0, 0)
                holder.position = [0, eye, 0] - eyeU * sc

                let pearl = Self.gloss(UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), metal: 0.25)
                let navy = Self.matte(UIColor(red: 0.12, green: 0.14, blue: 0.21, alpha: 1))
                var glass = PhysicallyBasedMaterial()
                glass.baseColor = .init(tint: UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1))
                glass.roughness = .init(floatLiteral: 0.04)
                glass.blending = .transparent(opacity: .init(floatLiteral: 0.1))
                func paint(_ e: Entity?, _ m: any RealityKit.Material) {
                    guard let e else { return }
                    if let me = e as? ModelEntity, let n = me.model?.materials.count { me.model?.materials = Array(repeating: m, count: max(1, n)) }
                    e.children.forEach { paint($0, m) }
                }
                paint(group("Material2_23"), pearl)                                // body paint → Motial pearl
                paint(group("Material2_15"), navy)                                 // dash trim: plain navy, no third-party badge
                paint(group("Material2"), EnvironmentBuilder.glow(Palette.teal))   // bonnet emblem → a teal Motial dot
                paint(group("Material2_28"), glass)                                // clear windscreen
                gauges.isEnabled = false                                           // stock gauge graphic → Motial cluster
                group("Material2_30")?.isEnabled = false                           // slogan number plates
                receiveLight(holder)
                cockpit.addChild(holder)
                carBody.isEnabled = false
                carLoaded = true
                // the Motial cluster sits in the driver's pod, where the car's gauges were
                let dash = holder.position + g * sc
                placeCluster(at: [0, dash.y + 0.02, dash.z + 0.06], scale: 0.72)
                wheel.position = [0, eye - 0.37, -0.43]
            }
        }
        if let w = try? await Entity(named: "RemerWheel", in: .main) {
            w.findEntity(named: "steering_wheel_a_steering_wheel_a_0")?.isEnabled = false   // the desk clamp
            let rim = w.findEntity(named: "steering_wheel_a_wheel") ?? w
            let rb = rim.visualBounds(relativeTo: w)
            let orient = Entity()
            // turns the rim to face the driver with its top forward (measured from the model's own geometry)
            orient.orientation = simd_quatf(ix: -0.32682, iy: 0.62705, iz: -0.32682, r: 0.62705)
            w.position = -rb.center
            orient.addChild(w)
            let k = 0.34 / max(rb.extents.z, 0.001)
            orient.scale = [k, k, k]
            receiveLight(orient)
            wheelProc.isEnabled = false
            wheelLoaded = true
            wheel.addChild(orient)
        }
    }

    private var veilShown: Float = -1
    private func setVeil(_ a: Float) {
        let a = max(0, min(1, a))
        guard abs(a - veilShown) > 0.01 || (a == 0 && veilShown != 0) else { return }
        veilShown = a
        veil.isEnabled = a > 0.005
        if var m = veil.model?.materials.first as? UnlitMaterial {
            m.blending = .transparent(opacity: .init(floatLiteral: a))
            veil.model?.materials = [m]
        }
    }

    private func placeCluster(at p: SIMD3<Float>, scale: Float) {
        cluster.position = p
        cluster.scale = [scale, scale, scale]
        cluster.orientation = simd_quatf(angle: -atan2(eye - p.y, -p.z), axis: [1, 0, 0])
    }

    // MARK: Start lights (3 · 2 · 1 · go): the car waits until go, like a race start

    private func addStartLights() {
        let g = Entity()
        let post = Self.gloss(UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), metal: 0.2)
        for s: Float in [-1, 1] {
            let p = ModelEntity(mesh: .generateBox(size: [0.14, 2.9, 0.14], cornerRadius: 0.05), materials: [post])
            p.position = [s * 2.45, 1.45, 0]
            g.addChild(p)
        }
        let beam = ModelEntity(mesh: .generateBox(size: [5.04, 0.12, 0.14], cornerRadius: 0.05), materials: [post])
        beam.position.y = 2.9
        g.addChild(beam)
        let panel = ModelEntity(mesh: .generateBox(size: [1.5, 0.5, 0.1], cornerRadius: 0.08),
                                materials: [Self.matte(UIColor(red: 0.08, green: 0.1, blue: 0.15, alpha: 1))])
        panel.position = [0, 2.55, 0]
        g.addChild(panel)
        for i in 0..<3 {
            let l = ModelEntity(mesh: .generateSphere(radius: 0.15), materials: [EnvironmentBuilder.glow(UIColor(white: 0.25, alpha: 1))])
            l.position = [Float(i - 1) * 0.45, 2.55, 0.06]
            g.addChild(l)
            startLamps.append(l)
        }
        things.append(Thing(e: g, z: -7, x: 0, kind: .fixed))
        world.addChild(g)
    }

    private func updateCountdown(dt: Float) {
        guard countdown > 0 else { return }
        let before = countdown
        countdown -= dt
        let elapsed = Self.countdownLength - countdown
        for i in 0..<3 where elapsed >= 0.5 + Float(i) && Self.countdownLength - before < 0.5 + Float(i) {
            startLamps[i].model?.materials = [EnvironmentBuilder.glow(Palette.gold)]
            SoundManager.shared.play("sfx_count_beep", volume: 0.5)
            feedback = "\(3 - i)"
        }
        if countdown <= 0 {
            for l in startLamps { l.model?.materials = [EnvironmentBuilder.glow(Palette.teal)] }
            SoundManager.shared.play("sfx_count_go", volume: 0.6)
            feedback = "Go! Point your toes down slowly"
        }
    }

    // MARK: Ease-off guide (after Forza's braking line): bars before each gate show whether your speed is right

    private func addGuide() {
        for _ in 0..<9 {
            let bar = ModelEntity(mesh: .generatePlane(width: 0.95, depth: 0.16, cornerRadius: 0.05),
                                  materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.85)])
            bar.isEnabled = false
            world.addChild(bar)
            guideBars.append(bar)
        }
    }

    private func updateGuide() {
        let next = things.filter { $0.kind == .gate && !$0.done && $0.z + distance < -1 && $0.z + distance > -26 }
            .max { $0.z < $1.z }
        guard let gate = next else { guideBars.forEach { $0.isEnabled = false }; guideState = -1; return }
        let gz = gate.z + distance
        let ratio = speed / Self.gateSpeed
        let state = ratio <= 1.06 ? 0 : (ratio <= 1.3 ? 1 : 2)          // teal: right · gold: ease off · coral: too fast
        if state != guideState {
            guideState = state
            let c: UIColor = state == 0 ? Palette.teal : (state == 1 ? Palette.gold : UIColor(red: 1, green: 0.5, blue: 0.42, alpha: 1))
            for b in guideBars { b.model?.materials = [EnvironmentBuilder.glow(c, opacity: 0.85)] }
        }
        for (k, b) in guideBars.enumerated() {
            let z = gz + 1.2 + Float(k) * 1.5
            b.isEnabled = z < -0.6
            b.position = [0, 0.032, z]
        }
    }

    // MARK: Windscreen head-up display: coaching floats on the glass, just above the horizon

    private func updateWindscreen(dt: Float) {
        let text = feedback ?? ""
        if text != shownHUD {
            shownHUD = text
            hudAge = 0
            Array(hud.children).forEach { $0.removeFromParent() }
            guard !text.isEmpty else { return }
            let mesh = MeshResource.generateText(text, extrusionDepth: 0.0005, font: .systemFont(ofSize: 0.024, weight: .semibold),
                                                 containerFrame: CGRect(x: 0, y: 0, width: 0.56, height: 0.2),
                                                 alignment: .center, lineBreakMode: .byWordWrapping)
            let tx = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: text.hasPrefix("★") || text.hasPrefix("Go") ? Palette.gold : .white)])
            let tb = tx.visualBounds(relativeTo: nil)
            tx.position = [-tb.center.x, -tb.center.y, 0.002]
            let w = tb.extents.x + 0.05, h = tb.extents.y + 0.03
            let back = ModelEntity(mesh: .generatePlane(width: w, height: h, cornerRadius: min(h / 2, 0.03)),
                                   materials: [EnvironmentBuilder.glow(UIColor(red: 0.03, green: 0.06, blue: 0.11, alpha: 1), opacity: 0.5)])
            hud.addChild(back)
            hud.addChild(tx)
        }
        hudAge += dt
        let keep = doneTimer > 0 || countdown > 0
        let a: Float = keep ? 1 : max(0, min(1, (6 - hudAge) / 0.6))       // messages fade after ~6 s
        hud.components.set(OpacityComponent(opacity: a))
    }

    // MARK: Festive scenery (far away, slow: calm motion only)

    /// Hot-air balloons drifting in the sunrise ("Hot Air Balloon - Low Poly" by Styro, Sketchfab, CC BY 4.0) recoloured
    /// in Motial's palette, and white wind turbines turning slowly on the fields ("Windmill, Low-Poly" by FLAREMEDIA,
    /// Sketchfab, CC BY 4.0). Everything is far from the road and moves far below 0.2 Hz, so it adds life, not sway.
    private func loadScenery() async {
        if let model = try? await Entity(named: "RemerBalloon", in: .main) {
            let mb = model.visualBounds(relativeTo: nil)
            let spots: [(SIMD3<Float>, Float, String?)] = [
                ([-26, 12, -58], 14, nil), ([20, 18, -72], 16, "tex_balloon_coral"), ([-8, 24, -96], 18, "tex_balloon_gold"),
                ([36, 10, -44], 12, "tex_balloon_lavender"), ([-44, 16, -36], 14, "tex_balloon_teal"),
                ([10, 30, -125], 20, "tex_balloon_coral"), ([-62, 22, -90], 17, "tex_balloon_gold"), ([58, 26, -110], 18, "tex_balloon_teal")]
            for (i, s) in spots.enumerated() {
                let b = model.clone(recursive: true)
                if let name = s.2, let mat = Self.retexture(name) { Self.apply(mat, to: b) }
                let h = Entity()
                b.position = -mb.center
                h.addChild(b)
                let k = s.1 / max(mb.extents.y, 0.001)
                h.scale = [k, k, k]
                h.orientation = simd_quatf(angle: Float(i) * 0.9, axis: [0, 1, 0])
                h.position = s.0
                stage.addChild(h)
                receiveLight(h)
                balloons.append((h, s.0, Float(i) * 1.7))
            }
        }
        if let model = try? await Entity(named: "RemerWindmill", in: .main) {
            // put the rotor on a pivot at its hub so the blades turn about their own axis
            var axis = SIMD3<Float>(0, 0, 1)
            if let turn = model.findEntity(named: "Turn"), let parent = turn.parent {
                let c = turn.visualBounds(relativeTo: parent).center
                let pivot = Entity()
                pivot.name = "RotorPivot"
                pivot.position = c
                parent.addChild(pivot)
                var tf = turn.transform
                tf.translation -= c
                turn.removeFromParent()
                pivot.addChild(turn)
                turn.transform = tf
                axis = simd_normalize(parent.convert(direction: [0, 0, 1], from: model))
            }
            let mb = model.visualBounds(relativeTo: nil)
            for k in 0..<4 {
                let side: Float = k % 2 == 0 ? -1 : 1
                let w = model.clone(recursive: true)
                let h = Entity()
                w.position = -[mb.center.x, mb.min.y, mb.center.z]
                h.addChild(w)
                let sc = Float.random(in: 22...28) / max(mb.extents.y, 0.001)
                h.scale = [sc, sc, sc]
                h.orientation = simd_quatf(angle: Float.random(in: -0.35...0.35), axis: [0, 1, 0])
                things.append(Thing(e: h, z: -Float(k) * 22.5 - 14, x: side * Float.random(in: 19...27), kind: .scenery))
                world.addChild(h)
                receiveLight(h)
                if let r = w.findEntity(named: "RotorPivot") { rotors.append((r, axis, Float(k) * 1.3)) }
            }
            placeThings()
        }
    }

    private func animateScenery() {
        for b in balloons {      // a slow rise and fall (≈ 0.05 Hz) and a lazy drift
            b.e.position = b.base + [sin(t * 0.06 + b.phase) * 2, sin(t * 0.3 + b.phase) * 0.6, 0]
        }
        for r in rotors { r.e.orientation = simd_quatf(angle: t * 0.55 + r.phase, axis: r.axis) }
    }

    private static func retexture(_ name: String) -> PhysicallyBasedMaterial? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "png"),
              let tex = try? TextureResource.load(contentsOf: u) else { return nil }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(tex))
        m.roughness = .init(floatLiteral: 0.6)
        return m
    }

    private static func apply(_ m: PhysicallyBasedMaterial, to e: Entity) {
        if let me = e as? ModelEntity, let n = me.model?.materials.count { me.model?.materials = Array(repeating: m, count: max(1, n)) }
        e.children.forEach { apply(m, to: $0) }
    }

    private func receiveLight(_ e: Entity) {
        guard let l = ibl else { return }
        if e is ModelEntity { e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: l)) }
        e.children.forEach { receiveLight($0) }
    }

    /// Flower patches along both sides of the road (pink, gold, white, violet, coral) that stream past with the grass.
    private func addFlowers() {
        let colours: [UIColor] = [Palette.pink, Palette.gold, UIColor(white: 0.97, alpha: 1), Palette.violet,
                                  UIColor(red: 1, green: 0.55, blue: 0.45, alpha: 1)]
        let meshes = (0..<3).compactMap { _ in Self.flowerPatch() }
        guard !meshes.isEmpty else { return }
        var k = 0
        for row in 0..<15 {
            for side: Float in [-1, 1] {
                let m = ModelEntity(mesh: meshes[k % meshes.count], materials: [Self.matte(colours[k % colours.count])])
                k += 1
                things.append(Thing(e: m, z: -Float(row) * 6 - (side > 0 ? 3 : 0), x: side * Float.random(in: 3.5...4.8), kind: .scenery))
                world.addChild(m)
            }
        }
        placeThings()
    }

    /// One mesh holding a loose patch of small blossoms (flattened octahedra), cheap to draw.
    private static func flowerPatch() -> MeshResource? {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        let faces: [[UInt32]] = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
        for _ in 0..<70 {
            let c = SIMD3<Float>(Float.random(in: -1.2...1.2), Float.random(in: 0.08...0.3), Float.random(in: -1.5...1.5))
            let r = Float.random(in: 0.045...0.075), h = r * 0.45
            let base = UInt32(pos.count)
            let v: [SIMD3<Float>] = [[r, 0, 0], [-r, 0, 0], [0, h, 0], [0, -h, 0], [0, 0, r], [0, 0, -r]]
            for p in v { pos.append(c + p); nrm.append(simd_normalize(p)) }
            for f in faces { idx += f.map { $0 + base } }
        }
        var md = MeshDescriptor(name: "flowers")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(nrm)
        md.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [md])
    }

    /// A small triangular pennant, visible from both sides.
    static func pennant() -> MeshResource? {
        var md = MeshDescriptor(name: "pennant")
        md.positions = MeshBuffers.Positions([[-0.11, 0, 0], [0.11, 0, 0], [0, -0.2, 0]])
        md.normals = MeshBuffers.Normals([[0, 0, 1], [0, 0, 1], [0, 0, 1]])
        md.primitives = .triangles([0, 2, 1, 0, 1, 2])
        return try? MeshResource.generate(from: [md])
    }

    /// A finish arch with a soft navy-and-white chequered banner and lantern-gold lettering.
    private func addFinish() {
        let g = Entity()
        let pearl = Self.gloss(UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), metal: 0.2)
        for s: Float in [-1, 1] {
            let p = ModelEntity(mesh: .generateBox(size: [0.2, 3.1, 0.2], cornerRadius: 0.06), materials: [pearl])
            p.position = [s * 2.45, 1.55, 0]
            g.addChild(p)
            let top = ModelEntity(mesh: .generateSphere(radius: 0.2), materials: [EnvironmentBuilder.glow(Palette.gold)])
            top.position = [s * 2.45, 3.25, 0]
            g.addChild(top)
        }
        let navy = UIColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1)
        for row in 0..<2 {
            for i in 0..<16 {
                let c = (i + row) % 2 == 0 ? UIColor(white: 0.96, alpha: 1) : navy
                let sq = ModelEntity(mesh: .generateBox(size: [0.3, 0.25, 0.05]), materials: [EnvironmentBuilder.glow(c)])
                sq.position = [-2.25 + Float(i) * 0.3, 2.62 + Float(row) * 0.25, 0]
                g.addChild(sq)
            }
        }
        let word = LiveAnkle.text("FINISH", size: 0.34, color: Palette.gold)
        let wb = word.visualBounds(relativeTo: nil)
        word.position = [-wb.center.x, 3.0 - wb.min.y, 0]
        g.addChild(word)
        things.append(Thing(e: g, z: -Self.runLength, x: 0, kind: .finish))
        world.addChild(g)
    }

    // MARK: Instruments

    private func updateInstruments() {
        setDial(&speedDial, speed * 3.6 / Self.dialMaxKmh, number: Int((speed * 3.6).rounded()), suffix: "")
        setDial(&ankleDial, footValue, number: Int((footValue * 20).rounded()) * 5, suffix: "%")
        progressHolder.scale = [max(0.001, progress), 1, 1]
        let key = "\(orbsCollected)|\(cleanGates)/\(gatesPassed)|\(Int(t))"
        if key != centreKey {
            centreKey = key
            centreText?.removeFromParent()
            let box = Entity()
            let lines: [(String, UIColor)] = [("\(orbsCollected) orbs", UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 1)),
                                              ("\(cleanGates)/\(gatesPassed) gates", Palette.gold),
                                              (GameRecordsCard.clock(Double(t)), UIColor(white: 0.8, alpha: 1))]
            for (i, l) in lines.enumerated() {
                let tx = LiveAnkle.text(l.0, size: 0.0115, color: l.1)
                let b = tx.visualBounds(relativeTo: nil)
                tx.position = [-b.center.x, 0.021 - Float(i) * 0.017 - b.min.y, 0.001]
                box.addChild(tx)
            }
            cluster.addChild(box)
            centreText = box
        }
        // surfaces flow past (optic flow); offsets wrap to keep precision
        if var m = groundMat, let g = ground {
            m.textureCoordinateTransform.offset = [0, Self.flow * (distance / 3).truncatingRemainder(dividingBy: 1)]
            g.model?.materials = [m]
        }
        if var m = roadMat, let r = roadSurface {
            m.textureCoordinateTransform.offset = [0, Self.flow * (distance / (90 / 34)).truncatingRemainder(dividingBy: 1)]
            r.model?.materials = [m]
        }
    }

    private func setDial(_ dial: inout Dial?, _ v: Float, number: Int, suffix: String) {
        guard var d = dial else { return }
        let v = max(0, min(1, v))
        d.needle.orientation = simd_quatf(angle: Self.dialAngle(v), axis: [0, 0, 1])
        let lit = Int((v * Float(d.ticks.count - 1)).rounded())
        if lit != d.lit {
            d.lit = lit
            for (i, tk) in d.ticks.enumerated() {
                tk.model?.materials = [i <= lit && v > 0.01 ? EnvironmentBuilder.glow(d.accent) : EnvironmentBuilder.glow(.white, opacity: 0.3)]
            }
        }
        if number != d.shown {
            d.shown = number
            Array(d.readout.children).forEach { $0.removeFromParent() }
            let tx = LiveAnkle.text("\(number)\(suffix)", size: 0.017, color: .white)
            let b = tx.visualBounds(relativeTo: nil)
            tx.position = [-b.center.x, -0.036 - b.min.y, 0]
            d.readout.addChild(tx)
        }
        dial = d
    }

    /// 0 → bottom left (225°), 1 → bottom right (−45°), sweeping clockwise like a car gauge.
    static func dialAngle(_ v: Float) -> Float { (225 - 270 * max(0, min(1, v))) * .pi / 180 }

    private func makeDial(x: Float, labels: [String], title: String, accent: UIColor, mark: Float?) -> Dial {
        let R: Float = 0.072
        let d = Entity()
        d.position = [x, 0, 0]
        cluster.addChild(d)
        let face = ModelEntity(mesh: .generatePlane(width: 2 * R, height: 2 * R, cornerRadius: R),
                               materials: [EnvironmentBuilder.glow(UIColor(red: 0.05, green: 0.08, blue: 0.13, alpha: 1))])
        d.addChild(face)
        if let ring = EnvironmentBuilder.annulus(inner: R, outer: R + 0.005) {
            let bezel = ModelEntity(mesh: ring, materials: [Self.gloss(UIColor(white: 0.85, alpha: 1), metal: 0.8)])
            bezel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            bezel.position.z = 0.001
            d.addChild(bezel)
        }
        var ticks: [ModelEntity] = []
        let n = 24
        for i in 0...n {
            let a = Self.dialAngle(Float(i) / Float(n))
            let major = i % 6 == 0
            let len: Float = major ? 0.013 : 0.007
            let tk = ModelEntity(mesh: .generatePlane(width: len, height: major ? 0.003 : 0.0018),
                                 materials: [EnvironmentBuilder.glow(.white, opacity: 0.3)])
            let r = R - 0.007 - len / 2
            tk.position = [cos(a) * r, sin(a) * r, 0.001]
            tk.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            d.addChild(tk)
            ticks.append(tk)
            if major {
                let lab = LiveAnkle.text(labels[i / 6], size: 0.0105, color: UIColor(white: 0.85, alpha: 1))
                let b = lab.visualBounds(relativeTo: nil)
                let rr = R - 0.032
                lab.position = [cos(a) * rr - b.center.x, sin(a) * rr - b.center.y, 0.001]
                d.addChild(lab)
            }
        }
        if let m = mark {   // gold notch: the speed that takes a lantern gate smoothly
            let a = Self.dialAngle(m)
            let notch = ModelEntity(mesh: .generatePlane(width: 0.014, height: 0.005, cornerRadius: 0.002), materials: [EnvironmentBuilder.glow(Palette.gold)])
            notch.position = [cos(a) * (R + 0.01), sin(a) * (R + 0.01), 0.0015]
            notch.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
            d.addChild(notch)
        }
        let cap = LiveAnkle.text(title, size: 0.0072, color: UIColor(white: 0.62, alpha: 1))
        let cb = cap.visualBounds(relativeTo: nil)
        cap.position = [-cb.center.x, -0.055 - cb.min.y, 0.001]
        d.addChild(cap)
        let readout = Entity()
        readout.position.z = 0.001
        d.addChild(readout)
        let needle = Entity()
        needle.position.z = 0.003
        let len = R - 0.01
        let blade = ModelEntity(mesh: .generatePlane(width: len, height: 0.0042, cornerRadius: 0.002), materials: [EnvironmentBuilder.glow(accent)])
        blade.position.x = len / 2 - 0.008
        needle.addChild(blade)
        needle.orientation = simd_quatf(angle: Self.dialAngle(0), axis: [0, 0, 1])
        d.addChild(needle)
        let hub = ModelEntity(mesh: .generatePlane(width: 0.016, height: 0.016, cornerRadius: 0.008), materials: [EnvironmentBuilder.glow(UIColor(white: 0.92, alpha: 1))])
        hub.position.z = 0.004
        d.addChild(hub)
        return Dial(needle: needle, ticks: ticks, accent: accent, readout: readout)
    }

    /// The instrument cluster, tilted to face the driver's eyes: speedometer (left, gold notch = smooth gate speed),
    /// "toes down" dial (right: your ankle, the accelerator) and a centre screen with orbs, gates, time and course.
    private func buildCluster() {
        let drop: Float = 0.15, ahead: Float = 0.62
        cluster.position = [0, eye - drop, -ahead]
        cluster.orientation = simd_quatf(angle: -atan2(drop, ahead), axis: [1, 0, 0])
        let plate = ModelEntity(mesh: .generatePlane(width: 0.48, height: 0.18, cornerRadius: 0.09),
                                materials: [EnvironmentBuilder.glow(UIColor(red: 0.035, green: 0.05, blue: 0.09, alpha: 1))])
        plate.position.z = -0.003
        cluster.addChild(plate)
        speedDial = makeDial(x: -0.145, labels: ["0", "5", "10", "15", "20"], title: "km/h", accent: Palette.gold,
                             mark: Self.gateSpeed * 3.6 / Self.dialMaxKmh)
        ankleDial = makeDial(x: 0.145, labels: ["0", "25", "50", "75", "100"], title: "TOES DOWN", accent: Palette.teal, mark: nil)
        let screen = ModelEntity(mesh: .generatePlane(width: 0.1, height: 0.095, cornerRadius: 0.014),
                                 materials: [EnvironmentBuilder.glow(UIColor(red: 0.06, green: 0.1, blue: 0.16, alpha: 1))])
        screen.position.z = -0.001
        cluster.addChild(screen)
        let track = ModelEntity(mesh: .generatePlane(width: 0.08, height: 0.005, cornerRadius: 0.0025), materials: [EnvironmentBuilder.glow(.white, opacity: 0.18)])
        track.position = [0, -0.035, 0.001]
        cluster.addChild(track)
        let bar = ModelEntity(mesh: .generatePlane(width: 0.08, height: 0.005, cornerRadius: 0.0025), materials: [EnvironmentBuilder.glow(Palette.teal)])
        bar.position.x = 0.04
        progressHolder.position = [-0.04, -0.035, 0.0015]
        progressHolder.scale = [0.001, 1, 1]
        progressHolder.addChild(bar)
        cluster.addChild(progressHolder)
        let course = LiveAnkle.text("COURSE", size: 0.006, color: UIColor(white: 0.55, alpha: 1))
        let cb = course.visualBounds(relativeTo: nil)
        course.position = [-cb.center.x, -0.044 - cb.min.y, 0.001]
        cluster.addChild(course)
        inputsHUD.position = [0, 0.112, 0.002]
        cluster.addChild(inputsHUD)
        cockpit.addChild(cluster)
    }

    // MARK: Cockpit: a calm open roadster
    // Pearl body, navy padding and a Motial teal stripe. No roof, pillars or halo: only a short bonnet edge, low doors and
    // the dashboard sit low in view, so the road and sky stay open while the car still gives a still rest frame.

    private static func matte(_ c: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: 0.95)
        return m
    }

    private static func gloss(_ c: UIColor, metal: Float = 0.1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.metallic = .init(floatLiteral: metal)
        m.roughness = .init(floatLiteral: 0.25)
        m.clearcoat = .init(floatLiteral: 1)
        m.clearcoatRoughness = .init(floatLiteral: 0.08)
        return m
    }

    private func buildCockpit() {
        let e = eye
        let pearl = Self.gloss(UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), metal: 0.2)
        let navy = Self.matte(UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
        let teal = Self.gloss(Palette.teal)
        func box(_ size: SIMD3<Float>, _ r: Float, _ m: PhysicallyBasedMaterial, _ p: SIMD3<Float>) {
            let b = ModelEntity(mesh: .generateBox(size: size, cornerRadius: r), materials: [m])
            b.position = p
            carBody.addChild(b)
        }
        box([1.25, 0.08, 1.1], 0.04, pearl, [0, e - 0.40, -1.32])           // short bonnet, low below the horizon
        box([0.14, 0.004, 1.06], 0, teal, [0, e - 0.358, -1.32])           // Motial stripe
        for s: Float in [-1, 1] {
            box([0.2, 0.12, 1.05], 0.055, pearl, [s * 0.62, e - 0.38, -1.3])    // soft front wings
            box([0.09, 0.13, 1.25], 0.04, pearl, [s * 0.76, e - 0.45, -0.2])    // low doors at the edge of view
        }
        box([1.42, 0.14, 0.4], 0.06, navy, [0, e - 0.36, -0.76])           // dashboard
        box([0.5, 0.2, 0.06], 0.03, navy, [0, e - 0.2, -0.7])              // binnacle behind the instruments
        cockpit.addChild(carBody)
        buildCluster()

        // steering wheel: navy rim, pearl spokes, teal Motial badge, gold top marker
        if let rim = Self.torus(major: 0.15, minor: 0.016) {
            wheelProc.addChild(ModelEntity(mesh: rim, materials: [Self.matte(UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1))]))
        }
        wheelProc.addChild(ModelEntity(mesh: .generateCylinder(height: 0.03, radius: 0.04), materials: [pearl]))
        let badge = ModelEntity(mesh: .generateCylinder(height: 0.034, radius: 0.018), materials: [EnvironmentBuilder.glow(Palette.teal)])
        wheelProc.addChild(badge)
        for a: Float in [0, 2.2, -2.2] {
            let spoke = ModelEntity(mesh: .generateBox(size: [0.15, 0.02, 0.016], cornerRadius: 0.007), materials: [pearl])
            spoke.position = [cos(a) * 0.075, 0, sin(a) * 0.085]
            spoke.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            wheelProc.addChild(spoke)
        }
        let marker = ModelEntity(mesh: .generateBox(size: [0.02, 0.024, 0.03]), materials: [EnvironmentBuilder.glow(Palette.gold)])
        marker.position = [0, 0.005, -0.15]
        wheelProc.addChild(marker)
        wheel.position = [0, e - 0.40, -0.47]
        wheel.addChild(wheelProc)
        cockpit.addChild(wheel)
        // placeholders only show if the real car or wheel can't be loaded
        carBody.isEnabled = false
        wheelProc.isEnabled = false
    }

    /// Torus lying in the XZ plane (used for the steering wheel rim).
    static func torus(major: Float, minor: Float, seg: Int = 64, side: Int = 12) -> MeshResource? {
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], idx: [UInt32] = []
        for i in 0...seg {
            let u = Float(i) / Float(seg) * 2 * .pi
            let c = SIMD3<Float>(cos(u) * major, 0, sin(u) * major)
            for j in 0...side {
                let v = Float(j) / Float(side) * 2 * .pi
                let n = SIMD3<Float>(cos(u) * cos(v), sin(v), sin(u) * cos(v))
                pos.append(c + n * minor); nrm.append(n)
            }
        }
        let w = UInt32(side + 1)
        for i in 0..<UInt32(seg) { for j in 0..<UInt32(side) {
            let a = i * w + j, b = (i + 1) * w + j
            idx += [a, a + 1, b, b, a + 1, b + 1]
        } }
        var md = MeshDescriptor(name: "torus")
        md.positions = MeshBuffers.Positions(pos)
        md.normals = MeshBuffers.Normals(nrm)
        md.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [md])
    }

    // MARK: Streaming world
    private func spawnInitial() {
        // lane dashes
        for k in 0..<22 {
            for x: Float in [-0.62, 0.62] {
                let d = ModelEntity(mesh: .generatePlane(width: 0.07, depth: 1.2), materials: [EnvironmentBuilder.glow(.white, opacity: 0.55)])
                things.append(Thing(e: d, z: -Float(k) * 4, x: x, kind: .dash))
                world.addChild(d)
            }
        }
        // kerbs: alternating white and teal blocks, Motial colours instead of race red
        for k in 0..<44 {
            for x: Float in [-2.07, 2.07] {
                let c: UIColor = k % 2 == 0 ? UIColor(white: 0.92, alpha: 1) : UIColor(red: 0.25, green: 0.78, blue: 0.78, alpha: 1)
                let kb = ModelEntity(mesh: .generateBox(size: [0.26, 0.03, 1.0]), materials: [Self.matte(c)])
                things.append(Thing(e: kb, z: -Float(k) * 2, x: x, kind: .dash))
                world.addChild(kb)
            }
        }
        // roadside lantern posts (warm, low contrast)
        for k in 0..<10 {
            for s: Float in [-1, 1] {
                let post = Entity()
                let pole = ModelEntity(mesh: .generateCylinder(height: 1.1, radius: 0.025), materials: [Self.matte(UIColor(red: 0.3, green: 0.22, blue: 0.16, alpha: 1))])
                pole.position.y = 0.55
                post.addChild(pole)
                let l = RhythmStepGame.makeLantern(scale: 0.9)
                l.position.y = 1.2
                post.addChild(l)
                things.append(Thing(e: post, z: -Float(k) * 9 - (s > 0 ? 4.5 : 0), x: s * 2.6, kind: .scenery))
                world.addChild(post)
            }
        }
        // orbs in lanes and gold gates: laid out along the whole run
        var z: Float = -18
        var lane = 1
        while z > -Self.runLength + 10 {
            if Int(-z) % 45 < 4 && z < -30 {
                // each lantern gate asks for one lane (steer there with the hands) at an easy speed (ease off with the foot)
                let gl = Self.laneX[[0, 2, 1][(gateLanes.count) % 3]]
                gateLanes[z] = gl
                let gate = Self.makeGate(laneX: gl)
                things.append(Thing(e: gate, z: z, x: 0, kind: .gate))
                world.addChild(gate)
                z -= 12
                continue
            }
            lane = max(0, min(2, lane + [-1, 0, 1].randomElement()!))
            for k in 0..<3 {
                let o = Entity()
                o.addChild(ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [EnvironmentBuilder.glow(UIColor(red: 0.92, green: 0.98, blue: 1, alpha: 1))]))
                o.addChild(ModelEntity(mesh: .generateSphere(radius: 0.18), materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.22)]))
                things.append(Thing(e: o, z: z - Float(k) * 2.2, x: Self.laneX[lane], kind: .orb))
                world.addChild(o)
            }
            z -= 15
        }
        placeThings()
    }

    static func makeGate(laneX: Float? = nil) -> Entity {
        let g = Entity()
        let mat = EnvironmentBuilder.glow(Palette.gold, opacity: 0.85)
        for s: Float in [-1, 1] {
            let p = ModelEntity(mesh: .generateBox(size: [0.08, 2.0, 0.08], cornerRadius: 0.03), materials: [mat])
            p.position = [s * 2.45, 1.0, 0]          // outside the kerbs: never inside the car, even in an outer lane
            g.addChild(p)
            let l = RhythmStepGame.makeLantern(scale: 1.2)
            l.position = [s * 2.45, 2.25, 0]
            g.addChild(l)
        }
        let beam = ModelEntity(mesh: .generateBox(size: [4.98, 0.08, 0.08], cornerRadius: 0.03), materials: [mat])
        beam.position.y = 2.0
        g.addChild(beam)
        if let lx = laneX {
            // the lane to take: a glowing gold pad on the road and a hanging lantern ring above it
            let band = ModelEntity(mesh: .generatePlane(width: 1.15, depth: 2.2, cornerRadius: 0.2), materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.35)])
            band.position = [lx, 0.009, 0]
            g.addChild(band)
            // a gold "this lane" chevron hanging from the beam, well above the car (nothing ever passes through the cabin)
            for side: Float in [-1, 1] {
                let bar = ModelEntity(mesh: .generateBox(size: [0.32, 0.06, 0.04], cornerRadius: 0.02),
                                      materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.95)])
                bar.position = [lx + side * 0.12, 1.86, 0]
                bar.orientation = simd_quatf(angle: side * 0.6, axis: [0, 0, 1])
                g.addChild(bar)
            }
            let drop = ModelEntity(mesh: .generateBox(size: [0.02, 0.1, 0.02]), materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.8)])
            drop.position = [lx, 1.96, 0]
            g.addChild(drop)
        } else {
            let band = ModelEntity(mesh: .generatePlane(width: 3.9, depth: 0.5), materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.25)])
            band.position.y = 0.008
            g.addChild(band)
        }
        // festive bunting in Motial colours along the beam
        if let flag = pennant() {
            let colours: [UIColor] = [Palette.teal, Palette.pink, Palette.gold, Palette.violet, UIColor(white: 0.97, alpha: 1)]
            for i in 0..<13 {
                let f = ModelEntity(mesh: flag, materials: [EnvironmentBuilder.glow(colours[i % colours.count], opacity: 0.95)])
                f.position = [-1.8 + Float(i) * 0.3, 1.96, 0]
                g.addChild(f)
            }
        }
        return g
    }

    private func loadTrees() async {
        // Realistic roadside trees (Poly Haven "Island Tree" and "Small Tree", CC0, reduced for Vision Pro); the older
        // low-poly birches ("Birch Trees Pack | PS1 Low Poly", Vova Truestory, CC BY 4.0) are the fallback.
        var models: [Entity] = []
        for name in ["TreeIsland01", "TreeSmall02", "TreeIsland02"] {
            if let m = try? await Entity(named: name, in: .main) { models.append(m) }
        }
        let realistic = !models.isEmpty
        if models.isEmpty, let m = try? await Entity(named: "Birches", in: .main) { models.append(m) }
        guard !models.isEmpty else { return }
        for k in 0..<8 {
            for side: Float in [-1, 1] {
                let model = models[(k * 2 + (side > 0 ? 1 : 0)) % models.count]
                let b = model.visualBounds(relativeTo: nil)
                let s = (realistic ? Float.random(in: 5.5...8.0) : 4.2) / max(b.extents.y, 0.001)
                let c = model.clone(recursive: true)
                let h = Entity()
                c.position = -[b.center.x, b.min.y, b.center.z]
                h.addChild(c)
                let sc = s * Float.random(in: 0.8...1.15)
                h.scale = [sc, sc, sc]
                h.orientation = simd_quatf(angle: Float.random(in: 0...6.28), axis: [0, 1, 0])
                // realistic crowns are wide: keep them well clear of the road so nothing ever passes over the car
                things.append(Thing(e: h, z: -Float(k) * 11 - 3, x: side * Float.random(in: realistic ? 7.5...11 : 5.5...9), kind: .scenery))
                world.addChild(h)
                receiveLight(h)
            }
        }
    }

    private func placeThings() {
        for i in things.indices {
            let th = things[i]
            var y: Float = 0.024
            if th.kind == .orb { y = 0.45 + sin(t * 2 + th.z) * 0.04 }
            th.e.position = [th.x - carX, y, th.z + distance]
        }
    }

    // MARK: Update
    func update(dt: Float, time: Double, tracker: MotionTracker) {
        guard dt > 0 else { return }
        // hold everything (hidden) until the real car is in place; the start countdown begins once it is visible
        // The road and cockpit are switched off (not faded, so nothing turns see-through) until the real car and
        // wheel are in. Tested 28 Oct: the Simulator needed ~15 s, so the old 6 s limit let the drive start car-less.
        if !carReady && waitClock < 20 {
            waitClock += dt
            if !heldHidden { world.isEnabled = false; cockpit.isEnabled = false; heldHidden = true }
            setVeil(0.9)                       // dark, but the session panels and STOP stay visible
            return
        }
        if heldHidden { world.isEnabled = true; cockpit.isEnabled = true; heldHidden = false }
        t += dt
        // fade in at the start, out at the end (no sudden full-field motion)
        let targetFade: Float = doneTimer > 0 ? 0 : 1
        fade += (targetFade - fade) * min(1, dt * 1.2)
        if doneTimer > 0 {
            // at the end the scene itself fades out, so the pain check and summary panels stay readable
            setVeil(0)
            stage.components.set(OpacityComponent(opacity: fade))
        } else {
            setVeil((1 - fade) * 0.9)
        }
        guard !finished else { return }

        pedal.update(dt: dt, tracker: tracker)
        if let c = pedal.connectionChanged {
            feedback = c ? "Foot pedal connected. Point your toes down slowly to drive" : "Foot pedal lost. Cruise assist is driving until it's back"
        }
        // Foot input: the paired foot device (Motial Pedal), or cruise assist when it isn't connected (Simulator, phone
        // asleep): a gentle steady speed that eases off before each gate, so the drive never surges or stalls.
        footAssist = pedal.demo
        let nextGate = things.filter { $0.kind == .gate && !$0.done && $0.z + distance < -1 && $0.z + distance > -30 }.max { $0.z < $1.z }
        let assistTarget: Float = nextGate.map { $0.z + distance > -16 ? 0.42 : 0.62 } ?? 0.62
        assistPedal += (assistTarget - assistPedal) * min(1, dt * 0.8)
        let foot = footAssist ? assistPedal : pedal.value
        footValue = foot
        anatomy.update(value: footAssist ? assistPedal : pedal.value, velocity: footAssist ? 0 : pedal.velocity, dt: dt)
        if !footAssist { smoothSum += pedal.smooth * dt; smoothN += dt }

        // accelerator → speed, with capped, smooth acceleration
        let target = foot * (0.45 + 0.55 * (footAssist ? 1 : pedal.smooth)) * maxSpeed
        if target > speed { speed += min(Self.accel * dt, target - speed) }        // ≤ 1.2 m/s² speeding up
        else { speed -= min(0.7 * dt, speed - target) }                            // gentle coast when easing off
        updateCountdown(dt: dt)
        if countdown > 0 { speed = 0 }                       // the car waits for the start lights

        // Hands on the wheel. Hands are read in the car's own frame, so turning the head never steers. They are
        // low-pass filtered (hand tracking jitters by a few mm and drops frames), must be near the wheel to count,
        // and need a short, deliberate hold to take over or let go. Moving the hands left/right and tilting them
        // like a real wheel both steer; one hand on the wheel is enough. Arms resting = lane assist.
        // Hands are judged relative to the person's LIVE head position in the car frame (headset test 28 Oct: a box
        // around the modelled wheel missed real hands whenever the stage was placed from an early head reading).
        // Any hand held up in front of the body, between lap and chin, counts as "on the wheel".
        func local(_ p: SIMD3<Float>?) -> SIMD3<Float>? { p.map { stage.convert(position: $0, from: nil) } }
        let headL = stage.convert(position: tracker.head, from: nil)
        let wc = SIMD3<Float>(headL.x, headL.y - 0.45, headL.z - 0.4)   // where the hands rest on the wheel
        func onWheel(_ p: SIMD3<Float>?) -> SIMD3<Float>? {
            guard let p else { return nil }
            let d = p - headL
            return (abs(d.x) < 0.65 && d.y < -0.05 && d.y > -0.85 && d.z < -0.12 && d.z > -0.9) ? p : nil
        }
        let k = min(1, dt * 14)
        if let l = onWheel(local(tracker.leftHand)) { leftF = leftF.map { $0 + (l - $0) * k } ?? l } else { leftF = nil }
        if let r = onWheel(local(tracker.rightHand)) { rightF = rightF.map { $0 + (r - $0) * k } ?? r } else { rightF = nil }
        let anyHand = leftF != nil || rightF != nil
        if anyHand { handsSeen += dt; handsLost = 0 } else { handsLost += dt; handsSeen = 0 }
        if !handsOn && handsSeen > 0.25 { handsOn = true }
        if handsOn && handsLost > 0.6 { handsOn = false }

        var desired: Float = 0
        var assistX = carX
        if handsOn {
            if let l = leftF, let r = rightF {
                let dx = max(r.x - l.x, 0.08), dy = r.y - l.y
                let tilt = atan2(-dy, dx) / 0.55                       // + when the right hand drops (turn right)
                let lateral = ((l.x + r.x) / 2 - wc.x) / 0.2            // + when both hands move right
                desired = 0.6 * tilt + 0.7 * lateral
            } else if let h = leftF ?? rightF {
                let rest: Float = leftF != nil ? -0.17 : 0.17           // where that hand rests on the rim
                desired = (h.x - wc.x - rest) / 0.2
            } else {
                desired = steer                                         // a dropped frame: hold the wheel where it was
            }
            if abs(desired) < 0.08 { desired = 0 }                      // dead zone: only deliberate moves steer
            desired = max(-1, min(1, desired))
        } else {
            // lane assist: towards the next gate's lane when a gate is close, otherwise the next orbs (also the Simulator)
            if let g = nextGate, g.z + distance > -20, let gl = gateLanes[g.z] {
                assistX = gl
            } else if let next = things.filter({ $0.kind == .orb && !$0.done && $0.z + distance < -4 }).max(by: { $0.z < $1.z }) {
                assistX = next.x
            }
            desired = max(-1, min(1, (assistX - carX) * 1.2))
        }
        if handsOn != wasHands {
            wasHands = handsOn
            feedback = handsOn ? "Hands on the wheel. Move them left or right to steer" : "Arms resting. Lane assist is steering"
        }
        steer += (desired - steer) * min(1, dt * 4)
        wheel.orientation = simd_quatf(angle: -steer * 1.2, axis: [0, 0, 1]) * simd_quatf(angle: .pi / 2 - 0.45, axis: [1, 0, 0])
        if countdown <= 0 {                                             // the car stays put until the lights go green
            let targetX = handsOn ? steer * 1.25 : assistX
            carX += (max(-1.25, min(1.25, targetX)) - carX) * min(1, dt * (handsOn ? 1.6 : 0.9))   // smooth lane changes
        }
        roadGroup.position.x = -carX
        ground?.position.x = -carX            // the grass shifts with the road, so the road never slides over it
        updateInputsHUD()

        distance += speed * dt
        audio.update(speed01: speed / maxSpeed)
        updateInstruments()
        animateScenery()
        updateGuide()
        updateWindscreen(dt: dt)

        // stream things past; recycle dashes and scenery ahead
        for i in things.indices {
            var th = things[i]
            let z = th.z + distance
            if (th.kind == .dash || th.kind == .scenery) && z > 4 {
                th.z -= th.kind == .dash ? 88 : 90
                things[i] = th
            }
            let zz = things[i].z + distance
            var y: Float = 0.024
            switch th.kind {
            case .orb:
                y = 0.45 + sin(t * 2 + th.z) * 0.03
                if !th.done && zz > -2.3 {                         // at the car's nose: never through the bonnet
                    things[i].done = true
                    if abs(th.x - carX) < 0.55 {
                        orbsCollected += 1; score += 1
                        SoundManager.shared.play("sfx_orb", volume: 0.45)
                        sparkles.burst(at: th.e.position(relativeTo: nil), color: Palette.teal, count: 10, speed: 0.5, size: 0.01)
                    }
                    th.e.isEnabled = false
                }
            case .gate:
                if !th.done && zz > -14 && zz < -1 && !gateWarned && speed > Self.gateSpeed + 0.3 {
                    gateWarned = true
                    feedback = "Gate ahead: steer to the gold lane and ease off slowly"
                    SoundManager.shared.play("sfx_tick", volume: 0.4)
                }
                if !th.done && zz > 0 {
                    things[i].done = true
                    gatesPassed += 1
                    gateWarned = false
                    SoundManager.shared.play("sfx_gate_pass", volume: 0.55)
                    let inLane = abs((gateLanes[th.z] ?? carX) - carX) < 0.6
                    let calm = speed <= Self.gateSpeed + 0.15
                    if calm && inLane {
                        cleanGates += 1; score += 2
                        streak += 1; bestStreak = max(bestStreak, streak)
                        feedback = streak >= 2 ? "Smooth streak ×\(streak)! Your shin muscle is in control"
                                               : ["Smooth through the gate", "Lovely control", "Perfect ease-off"][cleanGates % 3]
                        SoundManager.shared.play("sfx_chime", volume: 0.5)
                    } else {
                        streak = 0
                        feedback = !calm && !inLane ? "Steer into the gold lane and ease off together"
                                 : (!inLane ? "Good ease-off. Steer into the gold lane next time"
                                            : "A little fast. Lift your toes slowly when the guide turns gold")
                        SoundManager.shared.play("sfx_tyre_slide", volume: 0.35)
                    }
                }
            case .finish:
                if !th.done && zz > -0.5 {
                    things[i].done = true
                    let p = th.e.position(relativeTo: nil)
                    for (k, c) in [Palette.gold, Palette.teal, Palette.pink, Palette.violet, UIColor.white].enumerated() {
                        sparkles.burst(at: p + [Float(k - 2) * 0.9, 2.4, 0], color: c, count: 14, speed: 0.8, size: 0.02)
                    }
                }
            default: break
            }
            things[i].e.position = [th.x - carX, y, zz]
        }

        if progress >= 1 && doneTimer == 0 {
            doneTimer = 0.001
            SoundManager.shared.play("sfx_levelup", volume: 0.7)
            let ratio = gatesPassed > 0 ? Float(cleanGates) / Float(gatesPassed) : 0
            let stars = ratio >= 0.99 ? 3 : (ratio >= 0.5 ? 2 : 1)
            feedback = String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars)
                + "  Finish! \(cleanGates)/\(gatesPassed) gates smooth · \(orbsCollected) orbs · best streak \(bestStreak)"
            ShinLink.shared.sendStatus("Finish · \(orbsCollected) orbs")
        }
        if doneTimer > 0 {
            doneTimer += dt
            speed *= max(0, 1 - dt * 1.5)
            if doneTimer > 2.5 { finished = true }
        }
        ShinLink.shared.sendStatus("Cockpit · \(Int(progress * 100))% · \(orbsCollected) orbs")
        sparkles.update(dt: dt)
    }

    /// Lumi flies just ahead of the car, over the next orb.
    var guidePoint: SIMD3<Float>? {
        guard let next = things.filter({ $0.kind == .orb && !$0.done && $0.z + distance < -3 }).max(by: { $0.z < $1.z }) else { return nil }
        return next.e.position(relativeTo: nil) + [0, 0.5, 0]
    }

    func handleTap(_ entity: Entity) -> Bool { false }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        audio.setPaused(paused)
    }

    /// Both inputs on the dashboard: hands (steering) and foot (accelerator), each live or assisted.
    private func updateInputsHUD() {
        let hands = handsOn ? "HANDS · STEERING" : "HANDS · LANE ASSIST"
        let foot = footAssist ? "FOOT · CRUISE ASSIST" : "FOOT · PEDAL LIVE"
        let key = hands + foot
        guard key != shownInputs else { return }
        shownInputs = key
        Array(inputsHUD.children).forEach { $0.removeFromParent() }
        for (i, item) in [(hands, handsOn), (foot, !footAssist)].enumerated() {
            let pill = Entity()
            let tx = LiveAnkle.text(item.0, size: 0.0085, color: item.1 ? UIColor(red: 0.30, green: 0.95, blue: 0.69, alpha: 1) : UIColor(white: 0.75, alpha: 1))
            let b = tx.visualBounds(relativeTo: nil)
            let bg = ModelEntity(mesh: .generatePlane(width: b.extents.x + 0.024, height: 0.024, cornerRadius: 0.012),
                                 materials: [EnvironmentBuilder.glow(UIColor(red: 0.03, green: 0.05, blue: 0.08, alpha: 1), opacity: 0.9)])
            tx.position = [-b.center.x, -b.center.y, 0.001]
            pill.addChild(bg); pill.addChild(tx)
            pill.position = [Float(i == 0 ? -1 : 1) * 0.135, 0, 0]
            inputsHUD.addChild(pill)
        }
    }

    func stop() {
        finished = true
        audio.stop()
        sparkles.clear()
        root.removeFromParent()
    }
}
