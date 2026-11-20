import RealityKit
import UIKit
import Metal
import ImageIO
import simd

/// Rehabilitation spaces: a movement studio, a recovery room and a restorative garden.
///
/// Each space is a real 360° capture (Poly Haven, CC0) projected onto geometry with the true shape and size of the
/// place (walls, floor and ceiling of the room, or the terrace floor and a distant dome for the garden), seen from the
/// height the photo was taken. Because the photo sits on real surfaces at real distances, it keeps correct scale and
/// parallax as the person moves (unlike a flat sphere far away). Close to the person, where a photo would look soft,
/// everything is real 3D with physically based materials: an exercise mat or paving under the feet, and plants, a
/// bench or planters at the edges of the space. The coach, the HUD and the safety controls stay in front of a calm,
/// uncluttered area with enough contrast. Nothing in the space moves except leaves stirring very slowly.
/// The capture also lights everything (image-based light), so the coach and props belong to the place,
/// and spatial audio comes from where it would in reality (birds outside the window, a fountain in the garden).
@MainActor
enum RehabSpaces {

    enum Shape {
        /// Room walls (metres from the capture point, which is above the floor origin) and ceiling height.
        case room(xMin: Float, xMax: Float, zMin: Float, zMax: Float, ceiling: Float)
        /// Open air: flat floor out to `floor` metres, then a dome of `radius` metres.
        case open(floor: Float, radius: Float)
    }

    struct Prop {
        let model: String          // USDZ in the bundle (Poly Haven model converted for RealityKit)
        let position: SIMD3<Float> // on the floor, metres (−z = ahead)
        let yaw: Float             // degrees
        let height: Float          // metres (scales the model)
    }

    struct Floor {
        let texture: String
        let size: SIMD2<Float>
        let tile: Float
        let fade: Bool
    }

    struct Sound {
        let name: String
        let position: SIMD3<Float>
        let gain: Double
    }

    struct Spec {
        let image: String          // equirectangular capture (8K), u = 0.5 ahead
        let light: String          // small panorama for image-based light
        let captureHeight: Float   // camera height of the capture
        let shape: Shape
        let yaw: Float             // degrees: turns the capture so its calmest view is ahead
        let floor: Floor?          // real floor near the person
        let props: [Prop]
        let sounds: [Sound]
    }

    static func spec(_ kind: EnvironmentKind) -> Spec? {
        switch kind {
        case .physioStudio:
            // Poly Haven "Yoga Room" (Sergej Majboroda): a bright studio with wooden floor, mirrors and tall windows.
            return Spec(image: "env_studio", light: "env_studio_light", captureHeight: 1.62,
                        shape: .room(xMin: -5.2, xMax: 5.2, zMin: -6.6, zMax: 6.6, ceiling: 4.4), yaw: 0,
                        floor: Floor(texture: "tex_rubber_mat", size: SIMD2<Float>(2.2, 1.4), tile: 1.2, fade: false),
                        props: [Prop(model: "PropPachira", position: SIMD3<Float>(-2.6, 0, -3.4), yaw: 30, height: 1.8),
                                Prop(model: "PropCalathea", position: SIMD3<Float>(2.8, 0, -3.2), yaw: -20, height: 0.7),
                                Prop(model: "PropPlant02", position: SIMD3<Float>(3.4, 0, 1.8), yaw: 0, height: 1.1)],
                        sounds: [Sound(name: "amb_garden", position: SIMD3<Float>(0, 2.2, -6.4), gain: -14)])
        case .recoveryRoom:
            // Poly Haven "Lebombo" (Greg Zaal): a quiet, empty, sunlit room with a warm wooden floor.
            return Spec(image: "env_recovery", light: "env_recovery_light", captureHeight: 1.55,
                        shape: .room(xMin: -3.6, xMax: 3.6, zMin: -4.4, zMax: 4.4, ceiling: 3.0), yaw: 0,
                        floor: Floor(texture: "tex_rubber_mat", size: SIMD2<Float>(2.0, 1.3), tile: 1.2, fade: false),
                        props: [Prop(model: "PropCalathea", position: SIMD3<Float>(-2.2, 0, -2.6), yaw: 10, height: 0.75),
                                Prop(model: "PropPlant02", position: SIMD3<Float>(2.4, 0, -2.4), yaw: 0, height: 1.0)],
                        sounds: [Sound(name: "amb_garden", position: SIMD3<Float>(0, 1.8, -4.3), gain: -18)])
        case .restorativeGarden:
            // Poly Haven "Roof Garden" (Andreas Mischok): a green garden terrace with planting and paths.
            return Spec(image: "env_garden", light: "env_garden_light", captureHeight: 1.7,
                        shape: .open(floor: 12, radius: 40), yaw: 0,
                        floor: Floor(texture: "tex_patio", size: SIMD2<Float>(8, 8), tile: 2.0, fade: true),
                        props: [Prop(model: "PropPlanter", position: SIMD3<Float>(-2.4, 0, -2.6), yaw: 25, height: 0.75),
                                Prop(model: "PropShrub", position: SIMD3<Float>(2.6, 0, -2.8), yaw: 0, height: 1.0),
                                Prop(model: "PropFern", position: SIMD3<Float>(-2.9, 0, 0.6), yaw: 0, height: 0.6),
                                Prop(model: "PropBench", position: SIMD3<Float>(2.8, 0, 0.8), yaw: -90, height: 0.9)],
                        sounds: [Sound(name: "amb_garden", position: SIMD3<Float>(-6, 3, -8), gain: -8),
                                 Sound(name: "amb_garden", position: SIMD3<Float>(7, 3, 4), gain: -12)])
        default:
            return nil
        }
    }

    /// The whole space, centred on the person (y = 0 is the real floor).
    static func make(_ kind: EnvironmentKind, spec s: Spec) -> Entity {
        let root = Entity()
        root.name = "Environment"
        let content = Entity()
        content.orientation = simd_quatf(angle: s.yaw * .pi / 180, axis: [0, 1, 0])
        root.addChild(content)

        // 1. The capture on the true shape of the place
        if let u = Bundle.main.url(forResource: s.image, withExtension: "jpg"),
           let tex = try? TextureResource.load(contentsOf: u),
           let mesh = projected(capture: s.captureHeight, shape: s.shape) {
            var m = UnlitMaterial()
            let d = MTLSamplerDescriptor()
            d.sAddressMode = .repeat; d.tAddressMode = .clampToEdge
            d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; d.maxAnisotropy = 8
            m.color = .init(tint: .white, texture: .init(tex, sampler: .init(d)))
            let e = ModelEntity(mesh: mesh, materials: [m])
            e.name = "Backdrop"
            content.addChild(e)
        }

        // 2. Light from the place itself
        let light = Entity()
        Task { @MainActor in
            guard let u = Bundle.main.url(forResource: s.light, withExtension: "jpg")
                    ?? Bundle.main.url(forResource: s.image, withExtension: "jpg"),
                  let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                         kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
                  let env = try? await EnvironmentResource(equirectangular: img) else { return }
            light.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.6))
            light.orientation = content.orientation
            light.name = "SceneLight"                       // named only once lit: the session waits for this
            root.addChild(light)
            receive(root, light: light)
        }

        // 3. A real surface under the feet
        if let f = s.floor, let mat = tiledPBR(f.texture, tiles: [f.size.x / f.tile, f.size.y / f.tile]) {
            if f.fade {
                let r = f.size.x / 2
                let disc = ModelEntity(mesh: .generatePlane(width: r * 2, depth: r * 2, cornerRadius: r), materials: [mat])
                disc.name = "NearGround"; disc.position.y = 0.003
                content.addChild(disc)
                // soft edge into the photographed ground
                for i in 0..<6 {
                    let r0 = r + Float(i) * 0.5, r1 = r0 + 0.5
                    guard let ring = EnvironmentBuilder.annulus(inner: r0, outer: r1, segments: 96),
                          var m = tiledPBR(f.texture, tiles: [r1 * 2 / f.tile, r1 * 2 / f.tile]) else { continue }
                    m.blending = .transparent(opacity: .init(floatLiteral: 1 - (Float(i) + 0.5) / 6))
                    let e = ModelEntity(mesh: ring, materials: [m]); e.position.y = 0.003
                    content.addChild(e)
                }
            } else {
                // an exercise mat: rounded, slightly raised, so it reads as an object on the floor
                let mesh = MeshResource.generateBox(width: f.size.x, height: 0.008, depth: f.size.y, cornerRadius: 0.004)
                let matE = ModelEntity(mesh: mesh, materials: [mat])
                matE.name = "NearGround"; matE.position.y = 0.004
                root.addChild(matE)                                  // stays square to the person, not the room
            }
        }

        // 4. Real plants and furniture at the edges of the space (never in the exercise area)
        for p in s.props {
            Task { @MainActor in
                guard let model = try? await Entity(named: p.model, in: .main) else { return }
                let b = model.visualBounds(relativeTo: nil)
                let holder = Entity()
                model.position = [-b.center.x, -b.min.y, -b.center.z]
                holder.addChild(model)
                let k = p.height / max(b.extents.y, 0.001)
                holder.scale = [k, k, k]
                holder.position = p.position
                holder.orientation = simd_quatf(angle: p.yaw * .pi / 180, axis: [0, 1, 0])
                holder.components.set(GroundingShadowComponent(castsShadow: true))
                root.addChild(holder)
                if let l = root.findEntity(named: "SceneLight"), l.components.has(ImageBasedLightComponent.self) {
                    receive(holder, light: l)
                }
            }
        }

        // 5. Spatial sound from where it belongs
        for snd in s.sounds {
            let src = Entity()
            src.position = snd.position
            src.components.set(SpatialAudioComponent(gain: snd.gain))
            content.addChild(src)
            Task { @MainActor in
                if let res = try? AudioFileResource.load(named: snd.name + ".m4a", configuration: .init(shouldLoop: true)) {
                    src.playAudio(res)
                }
            }
        }
        return root
    }

    private static func receive(_ e: Entity, light: Entity) {
        if e is ModelEntity, e.name != "Backdrop" {
            e.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
        for c in e.children { receive(c, light: light) }
    }

    /// Physically based, tiling material from `<name>_diff.jpg`, `<name>_nor.jpg`, `<name>_rough.jpg`.
    static func tiledPBR(_ name: String, tiles: SIMD2<Float>) -> PhysicallyBasedMaterial? {
        guard let du = Bundle.main.url(forResource: name + "_diff", withExtension: "jpg"),
              let diff = try? TextureResource.load(contentsOf: du) else { return nil }
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear; d.maxAnisotropy = 8
        let sampler = MaterialParameters.Texture.Sampler(d)
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(diff, sampler: sampler))
        if let nu = Bundle.main.url(forResource: name + "_nor", withExtension: "jpg"),
           let nor = try? TextureResource.load(contentsOf: nu, options: .init(semantic: .normal)) {
            m.normal = .init(texture: .init(nor, sampler: sampler))
        }
        if let ru = Bundle.main.url(forResource: name + "_rough", withExtension: "jpg"),
           let rough = try? TextureResource.load(contentsOf: ru, options: .init(semantic: .raw)) {
            m.roughness = .init(scale: 1, texture: .init(rough, sampler: sampler))
        } else {
            m.roughness = .init(floatLiteral: 0.85)
        }
        m.textureCoordinateTransform = .init(offset: .zero, scale: tiles, rotation: 0)
        return m
    }

    /// The capture projected onto the place's real surfaces. Every vertex sits on a wall, floor, ceiling or dome
    /// along its own viewing ray from the capture point, so texture coordinates are exact (no seams or stretching
    /// except right below the tripod, which the mat or paving covers).
    static func projected(capture h: Float, shape: Shape, azSteps: Int = 288, elSteps: Int = 144) -> MeshResource? {
        var pos: [SIMD3<Float>] = []; var uv: [SIMD2<Float>] = []; var nrm: [SIMD3<Float>] = []
        let eye = SIMD3<Float>(0, h, 0)
        for i in 0...elSteps {
            // denser rows near the horizon, where most detail is
            let t: Float = Float(i) / Float(elSteps) * 2 - 1
            let warp: Float = t + 0.35 * t * (1 - abs(t))
            let el: Float = warp * Float.pi / 2
            for j in 0...azSteps {
                let az: Float = -Float.pi + 2 * Float.pi * Float(j) / Float(azSteps)
                let ce: Float = cos(el)
                let d = SIMD3<Float>(sin(az) * ce, sin(el), -cos(az) * ce)
                var dist: Float
                switch shape {
                case let .room(xMin, xMax, zMin, zMax, ceiling):
                    dist = .greatestFiniteMagnitude
                    if d.x > 1e-5 { dist = min(dist, xMax / d.x) }
                    if d.x < -1e-5 { dist = min(dist, xMin / d.x) }
                    if d.z > 1e-5 { dist = min(dist, zMax / d.z) }
                    if d.z < -1e-5 { dist = min(dist, zMin / d.z) }
                    if d.y < -1e-5 { dist = min(dist, h / -d.y) }
                    if d.y > 1e-5 { dist = min(dist, (ceiling - h) / d.y) }
                case let .open(_, radius):
                    dist = radius                                      // sky and far scenery on a distant dome
                    if d.y < -1e-5 { dist = min(radius, h / -d.y) }    // the ground on the real ground plane
                }
                pos.append(eye + d * dist)
                nrm.append(-d)
                let u: Float = 0.5 + az / (2 * Float.pi)
                let v: Float = 0.5 + el / Float.pi
                uv.append(SIMD2<Float>(u, v))
            }
        }
        var idx: [UInt32] = []
        let w = UInt32(azSteps + 1)
        for i in 0..<UInt32(elSteps) {
            for j in 0..<UInt32(azSteps) {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                idx += [a, b, c, b, d, c, a, c, b, b, c, d]
            }
        }
        var desc = MeshDescriptor(name: "space")
        desc.positions = MeshBuffers.Positions(pos)
        desc.normals = MeshBuffers.Normals(nrm)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }
}
