import SwiftUI
import RealityKit
import UIKit

struct AnatomyLandmarks: Codable {
    struct Lig: Codable { let a: [Float]; let b: [Float]; let r: Float; let bAttach: String }
    let anklePivot: [Float]
    let ligaments: [String: Lig]
    let sizeMeters: [Float]
}

enum AnatomyInfo {
    struct Item { let name: String; let kind: String; let text: String }
    static let items: [String: Item] = [
        "ATFL": Item(name: "Anterior talofibular ligament (ATFL)", kind: "Ligament",
                     text: "The most commonly injured ligament in an ankle sprain. It tightens when the foot points down and rolls in, which is exactly how most sprains happen."),
        "CFL": Item(name: "Calcaneofibular ligament (CFL)", kind: "Ligament",
                    text: "Injured in more severe sprains, usually together with the ATFL. It steadies the ankle when the heel rolls in."),
        "PTFL": Item(name: "Posterior talofibular ligament (PTFL)", kind: "Ligament", text: "The strongest outer ligament, and rarely torn."),
        "AITFL": Item(name: "Anterior inferior tibiofibular ligament", kind: "Ligament",
                      text: "Part of the syndesmosis that holds the shin bones together. Injury causes a 'high ankle sprain', which recovers more slowly."),
        "Deltoid_TN": Item(name: "Deltoid ligament", kind: "Ligament", text: "The strong fan of ligaments on the inner ankle. It is less often sprained."),
        "Deltoid_TC": Item(name: "Deltoid ligament", kind: "Ligament", text: "The strong fan of ligaments on the inner ankle. It is less often sprained."),
        "Deltoid_TT": Item(name: "Deltoid ligament", kind: "Ligament", text: "The strong fan of ligaments on the inner ankle. It is less often sprained."),
        "tibia": Item(name: "Tibia (shin bone)", kind: "Bone", text: "Carries most of your body weight. Its lower end forms the inner ankle bone (medial malleolus)."),
        "fibula": Item(name: "Fibula", kind: "Bone", text: "The thin outer leg bone. Its tip is the outer ankle bone (lateral malleolus), where the outer ligaments attach."),
        "talus": Item(name: "Talus", kind: "Bone", text: "Sits in the ankle mortise and lets the foot point up and down. No muscles attach to it, so ligaments and balance control keep it stable."),
        "calcaneus": Item(name: "Calcaneus (heel bone)", kind: "Bone", text: "The heel bone, which takes the landing forces when you walk and hop."),
        "navicular": Item(name: "Navicular", kind: "Bone", text: "The inner arch bone. Tenderness here is one of the Ottawa rule checks."),
        "cuboid": Item(name: "Cuboid", kind: "Bone", text: "The outer midfoot bone. The fibularis longus tendon runs under it."),
        "metatarsal_5": Item(name: "5th metatarsal", kind: "Bone", text: "The outer foot bone. Tenderness at its base after a sprain needs an X-ray (Ottawa foot rule)."),
        "fibularis_longus": Item(name: "Fibularis (peroneus) longus", kind: "Muscle", text: "Turns the sole outwards and reacts fast to stop the ankle rolling. Strengthening it is a key part of rehab."),
        "fibularis_brevis": Item(name: "Fibularis (peroneus) brevis", kind: "Muscle", text: "Works with fibularis longus to protect the outer ankle."),
        "tibialis_anterior": Item(name: "Tibialis anterior", kind: "Muscle", text: "Lifts the foot (dorsiflexion) so your toes clear the ground."),
        "achilles_tendon": Item(name: "Achilles tendon", kind: "Tendon", text: "Connects the calf to the heel. Heel raises train the calf–Achilles unit."),
        "long_plantar_ligament": Item(name: "Long plantar ligament", kind: "Ligament", text: "Supports the outer arch of the foot."),
        "phalanges": Item(name: "Toe bones (phalanges)", kind: "Bone", text: "Push-off at the toes is important for normal walking and hopping."),
    ]
    static func lookup(_ name: String) -> Item? {
        if let i = items[name] { return i }
        if name.hasPrefix("metatarsal") { return Item(name: "Metatarsal", kind: "Bone", text: "The long bones of the forefoot.") }
        if name.hasPrefix("cuneiform") { return Item(name: "Cuneiform", kind: "Bone", text: "The three wedge-shaped bones of the midfoot arch.") }
        return nil
    }
}

struct AnatomyVolumeView: View {
    @Environment(AppModel.self) private var model
    @State private var root = Entity()
    @State private var foot: Entity?
    @State private var ligaments: [String: ModelEntity] = [:]
    @State private var landmarks: AnatomyLandmarks?
    @State private var selected: AnatomyInfo.Item?
    @State private var showBones = true
    @State private var showSoft = true
    @State private var showLigaments = true
    @State private var spin: Float = 0
    @State private var zoom: Float = 1
    @State private var baseSpin: Float = 0
    @State private var baseZoom: Float = 1
    @State private var animating = false
    @State private var sprainAmount: Float = 0
    @State private var modelLoaded = false
    @State private var scanOpacity: Double = 0.9
    @State private var highlighted: Set<String> = []
    @State private var savedMaterials: [String: [any RealityKit.Material]] = [:]
    @State private var painMap = false
    @State private var painNote: String?

    private var focus: MedicalUpload? { model.uploads.first { $0.id == model.focusUploadID } }

    private let displayScale: Float = 2.3

    var body: some View {
        RealityView { content, attachments in
            content.add(root)
            guard let m = try? await Entity(named: "AnkleAnatomy", in: .main) else { return }
            m.scale = [displayScale, displayScale, displayScale]
            m.position = [0, -0.2, 0]
            root.addChild(m)
            foot = m.findEntity(named: "Foot")
            m.generateCollisionShapes(recursive: true)
            applyInputTargets(m)
            loadLigaments(into: m)
            if let card = attachments.entity(for: "info") {
                card.position = [0, 0.26, 0.05]
                root.addChild(card)
            }
            modelLoaded = true
        } update: { content, attachments in
            root.orientation = simd_quatf(angle: spin, axis: [0, 1, 0])
            root.scale = [zoom, zoom, zoom]
            setVisibility()
        } attachments: {
            Attachment(id: "info") {
                if let s = selected {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.kind.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(s.name).font(.title3.bold())
                        Text(s.text).font(.callout)
                    }
                    .padding(18).frame(width: 380).glassBackgroundEffect()
                }
            }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { v in select(v.entity) })
        .gesture(DragGesture().targetedToAnyEntity().onChanged { v in
            spin = baseSpin + Float(v.translation.width) * 0.01
        }.onEnded { _ in baseSpin = spin })
        .gesture(MagnifyGesture().targetedToAnyEntity().onChanged { v in
            zoom = max(0.6, min(1.8, baseZoom * Float(v.magnification)))
        }.onEnded { _ in baseZoom = zoom })
        .ornament(attachmentAnchor: .scene(.bottomFront)) { controls }
        .ornament(visibility: focus == nil ? .hidden : .visible, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) { scanPanel }
        .ornament(visibility: model.anatomyMode == .myInjury && focus == nil ? .visible : .hidden,
                  attachmentAnchor: .scene(.trailing), contentAlignment: .leading) { injuryPanel }
        .ornament(visibility: musclesExercise != nil && focus == nil ? .visible : .hidden,
                  attachmentAnchor: .scene(.trailing), contentAlignment: .leading) { musclePanel }
        .onChange(of: model.anatomyMode) { _, _ in applyHighlights() }
        .onChange(of: model.focusUploadID) { _, _ in applyHighlights() }
        .onChange(of: modelLoaded) { _, _ in applyHighlights() }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $showBones) { Label("Bones", systemImage: "circle.hexagongrid") }
            Toggle(isOn: $showSoft) { Label("Muscles", systemImage: "bolt.heart") }
            Toggle(isOn: $showLigaments) { Label("Ligaments", systemImage: "link") }
            Divider().frame(height: 30)
            Toggle(isOn: Binding(get: { model.anatomyMode == .myInjury }, set: { model.anatomyMode = $0 ? .myInjury : .explore })) {
                Label("My injury", systemImage: "scope")
            }
            Button { Task { await playSprain() } } label: { Label("How a sprain happens", systemImage: "play.fill") }
                .disabled(animating || !modelLoaded)
            Button { spin = 0; baseSpin = 0; zoom = 1; baseZoom = 1; selected = nil; model.anatomyMode = .explore } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
        }
        .toggleStyle(.button)
        .padding(14)
        .glassBackgroundEffect()
    }

    /// The person's own X-ray or report beside the 3D ankle, with the structures it mentions lit up.
    @ViewBuilder private var scanPanel: some View {
        if let u = focus {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(u.kind == .xray ? "Your X-ray" : "Your report", systemImage: "rectangle.on.rectangle.angled").font(.headline)
                    Spacer()
                    Button { model.focusUploadID = nil } label: { Image(systemName: "xmark") }.buttonBorderShape(.circle)
                }
                if let img = ReportReader.image(for: u) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 320).frame(maxHeight: 360)
                        .opacity(scanOpacity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Slider(value: $scanOpacity, in: 0.2...1) { Text("Opacity") }
                }
                if !u.findings.isEmpty {
                    Text("Tap to find it on the 3D ankle").font(.caption).foregroundStyle(.secondary)
                    ForEach(u.findings) { f in
                        Button {
                            if let k = f.structure { selected = AnatomyInfo.lookup(k); SoundManager.shared.say("\(f.term). \(f.meaning)") }
                            else { SoundManager.shared.say("\(f.term). \(f.meaning)") }
                        } label: {
                            Label(f.term, systemImage: f.structure != nil ? "scope" : "info.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(f.caution ? .orange : Theme.accent)
                    }
                }
                Text("Compare the shapes: fibula on the outside, tibia on the inside, talus in between. This is for learning, not diagnosis.")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 320, alignment: .leading)
            }
            .padding(18).frame(width: 360).glassBackgroundEffect()
        }
    }

    private var musclesExercise: Exercise? {
        if case .muscles(let id) = model.anatomyMode { return ExerciseLibrary.byID(id) }
        return nil
    }

    @ViewBuilder private var musclePanel: some View {
        if let ex = musclesExercise {
            VStack(alignment: .leading, spacing: 12) {
                Text(ex.title).font(.title3.bold())
                MusclesView(exercise: ex)
                Text("Glowing orange: the muscles and tendons shown in this model. Hip and thigh muscles work too.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { SoundManager.shared.say(ex.musclesSpoken) } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
            }
            .padding(18).frame(width: 360).glassBackgroundEffect()
        }
    }

    /// Where it most likely hurts (from the person's answers and report), plus a "point to where it hurts" mode.
    @ViewBuilder private var injuryPanel: some View {
        if let p = model.profile {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your injury", systemImage: "scope").font(.headline).foregroundStyle(.pink)
                ForEach(ClinicalEngine.injurySites(p, uploads: model.uploads)) { s in
                    Button {
                        selected = AnatomyInfo.lookup(s.structure)
                        SoundManager.shared.say("\(s.title). \(s.why)")
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.subheadline.bold())
                            Text(s.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                Toggle(isOn: $painMap) { Label("Point to where it hurts", systemImage: "hand.point.up.left") }
                if painMap {
                    Text(painNote ?? "Tap the spot on the 3D ankle that matches where your ankle is sore.")
                        .font(.callout).foregroundStyle(painNote == nil ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label("Avoid for now: " + ClinicalEngine.avoid(model.stage, p).prefix(3).map(\.text).joined(separator: "; ") + ".",
                      systemImage: "hand.raised.fill").font(.caption).foregroundStyle(.orange)
            }
            .padding(18).frame(width: 360).glassBackgroundEffect()
        }
    }

    private func painAdvice(for key: String, name: String) -> String {
        if ClinicalEngine.ottawaZones.contains(key) {
            return "\(name): if pressing on the bone here is very painful, or you couldn't take 4 steps, an X-ray may be needed (Ottawa Ankle Rules). Please get it checked before exercising."
        }
        switch key {
        case "ATFL", "CFL", "PTFL":
            return "\(name): this is the classic sprain spot on the outer ankle. It usually settles with your plan. Keep pain under 4/10 while exercising."
        case "AITFL":
            return "\(name): pain here suggests a high ankle sprain, which recovers more slowly. Ask a physiotherapist to check it."
        case "Deltoid_TN", "Deltoid_TC", "Deltoid_TT":
            return "\(name): pain on the inner ankle is less common in sprains. If it's marked, ask a clinician to check it."
        case "achilles_tendon":
            return "\(name): soreness here is common when walking more. Sudden pain with a 'kick' feeling needs urgent review."
        default:
            return "\(name): mention this spot to your clinician if it stays sore."
        }
    }

    private func applyHighlights() {
        guard let m = root.children.first else { return }
        var keys = Set(focus?.findings.compactMap(\.structure) ?? [])
        if model.anatomyMode == .myInjury, let p = model.profile {
            keys.formUnion(ClinicalEngine.injurySites(p, uploads: model.uploads).map(\.structure))
        }
        if let ex = musclesExercise {
            keys.formUnion(ex.muscles.compactMap(\.anatomyKey))
            if ex.muscles.contains(where: { $0.anatomyKey == "fibularis_longus" }) { keys.insert("fibularis_brevis") }
            showSoft = true
        }
        // restore previous
        for name in highlighted where !keys.contains(name) {
            if let e = m.findEntity(named: name) as? ModelEntity, let mats = savedMaterials[name] { e.model?.materials = mats }
        }
        for name in keys {
            guard let e = (ligaments[name] as Entity?) ?? m.findEntity(named: name), let me = e as? ModelEntity else { continue }
            if savedMaterials[name] == nil { savedMaterials[name] = me.model?.materials ?? [] }
            var mat = PhysicallyBasedMaterial()
            let injury = model.anatomyMode == .myInjury
            let working = musclesExercise != nil
            mat.baseColor = .init(tint: working ? UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
                                  : (injury ? UIColor(red: 1, green: 0.4, blue: 0.5, alpha: 1) : UIColor(red: 0.35, green: 0.9, blue: 0.95, alpha: 1)))
            mat.emissiveColor = .init(color: working ? UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
                                      : (injury ? UIColor(red: 1, green: 0.25, blue: 0.35, alpha: 1) : UIColor(red: 0.2, green: 0.85, blue: 0.95, alpha: 1)))
            mat.emissiveIntensity = 1.2
            me.model?.materials = Array(repeating: mat, count: max(1, me.model?.materials.count ?? 1))
        }
        highlighted = keys
        if let first = focus?.findings.first(where: { $0.structure != nil })?.structure { selected = AnatomyInfo.lookup(first) }
        else if model.anatomyMode == .myInjury, let p = model.profile, let s = ClinicalEngine.injurySites(p, uploads: model.uploads).first {
            selected = AnatomyInfo.lookup(s.structure)
        }
    }

    private func applyInputTargets(_ e: Entity) {
        if e is ModelEntity {
            e.components.set(InputTargetComponent())
            e.components.set(HoverEffectComponent())
        }
        for c in e.children { applyInputTargets(c) }
    }

    private func loadLigaments(into m: Entity) {
        guard let u = Bundle.main.url(forResource: "anatomy_landmarks", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let lm = try? JSONDecoder().decode(AnatomyLandmarks.self, from: d) else { return }
        landmarks = lm
        let container = Entity(); container.name = "Ligaments"
        m.addChild(container)
        var made: [String: ModelEntity] = [:]
        for (name, l) in lm.ligaments {
            let e = ModelEntity(mesh: .generateCylinder(height: 1, radius: l.r * 1.2), materials: [ligamentMaterial(strain: 0)])
            e.name = name
            e.components.set(InputTargetComponent())
            e.components.set(HoverEffectComponent())
            e.components.set(CollisionComponent(shapes: [.generateBox(size: [0.012, 1, 0.012])]))
            container.addChild(e)
            made[name] = e
        }
        ligaments = made
        updateLigaments()
    }

    private func ligamentMaterial(strain: Float) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        let t = CGFloat(max(0, min(1, strain / 0.25)))
        mat.baseColor = .init(tint: UIColor(red: 0.95, green: 0.82 - 0.65 * t, blue: 0.82 - 0.62 * t, alpha: 1))
        mat.emissiveColor = .init(color: UIColor(red: 1, green: 0.15, blue: 0.2, alpha: 1))
        mat.emissiveIntensity = Float(t) * 1.5
        mat.roughness = .init(floatLiteral: 0.35)
        return mat
    }

    /// Foot rotation about the ankle pivot. Inversion about +Z and plantarflexion about +X (right foot model).
    private func footRotation(_ amount: Float) -> simd_quatf {
        simd_quatf(angle: 0.55 * amount, axis: [0, 0, 1]) * simd_quatf(angle: 0.45 * amount, axis: [1, 0, 0])
    }

    private func updateLigaments() {
        guard let lm = landmarks else { return }
        let pivot = SIMD3<Float>(lm.anklePivot[0], lm.anklePivot[1], lm.anklePivot[2])
        let q = footRotation(sprainAmount)
        for (name, l) in lm.ligaments {
            guard let e = ligaments[name] else { continue }
            let a = SIMD3<Float>(l.a[0], l.a[1], l.a[2])
            let b0 = SIMD3<Float>(l.b[0], l.b[1], l.b[2])
            let b = l.bAttach == "Foot" ? pivot + q.act(b0 - pivot) : b0
            let rest = simd_distance(a, b0)
            let len = simd_distance(a, b)
            let dir = simd_normalize(b - a)
            e.position = (a + b) / 2
            e.orientation = simd_quatf(from: [0, 1, 0], to: dir)
            e.scale = [1, len, 1]
            e.model?.materials = [ligamentMaterial(strain: (len - rest) / max(rest, 0.001))]
        }
    }

    private func playSprain() async {
        animating = true
        selected = AnatomyInfo.lookup("ATFL")
        let steps = 40
        for phase in [1, -1] {
            for k in 0...steps {
                let u = Float(k) / Float(steps)
                let s = phase == 1 ? u : 1 - u
                sprainAmount = s * s * (3 - 2 * s)
                foot?.orientation = footRotation(sprainAmount)
                updateLigaments()
                try? await Task.sleep(for: .milliseconds(30))
            }
            if phase == 1 { try? await Task.sleep(for: .milliseconds(900)) }
        }
        animating = false
    }

    private func setVisibility() {
        guard let m = root.children.first else { return }
        let soft = ["fibularis_longus", "fibularis_brevis", "tibialis_anterior", "achilles_tendon", "long_plantar_ligament"]
        func walk(_ e: Entity) {
            if e.parent?.name == "Leg" || e.parent?.name == "Foot" {
                e.isEnabled = soft.contains(e.name) ? showSoft : showBones
            }
            for c in e.children { walk(c) }
        }
        walk(m)
        m.findEntity(named: "Ligaments")?.isEnabled = showLigaments
    }

    private func select(_ e: Entity) {
        var cur: Entity? = e
        while let c = cur {
            if let info = AnatomyInfo.lookup(c.name) {
                selected = info
                SoundManager.shared.play("sfx_tap", volume: 0.5)
                if painMap {
                    painNote = painAdvice(for: c.name, name: info.name)
                    SoundManager.shared.say(painNote ?? "")
                }
                return
            }
            cur = c.parent
        }
    }
}
