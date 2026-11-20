import RealityKit
import UIKit
import ImageIO
import Metal
import simd

/// Builds the virtual surroundings at three coverage levels:
/// 60° window and 180° panorama keep the real floor and sides visible (room view);
/// 360° wraps the person completely. It adds a virtual floor at the real floor height and is used for
/// standing work only after the space scan (the person can always turn the Digital Crown to see the room).
@MainActor
enum EnvironmentBuilder {
    private static var textures: [EnvironmentKind: TextureResource] = [:]

    static func texture(_ kind: EnvironmentKind) -> TextureResource? {
        if let t = textures[kind] { return t }
        // "_ground" variant: same painting with a brighter, natural ground below the horizon
        guard let u = Bundle.main.url(forResource: kind.imageName + "_ground", withExtension: "jpg")
                ?? Bundle.main.url(forResource: kind.imageName, withExtension: "jpg"),
              let t = try? TextureResource.load(contentsOf: u) else { return nil }
        textures[kind] = t
        return t
    }

    static func make(_ requested: EnvironmentKind, coverage: EnvironmentCoverage) -> Entity {
        // a space whose capture isn't in the build falls back to the meadow, so the scene is never empty
        var kind = requested
        if requested.isSpace, Bundle.main.url(forResource: requested.imageName, withExtension: "jpg") == nil { kind = .goldenMeadow }
        if coverage == .full360, let spec = RehabSpaces.spec(kind),
           Bundle.main.url(forResource: spec.image, withExtension: "jpg") != nil {
            return RehabSpaces.make(kind, spec: spec)
        }
        let root = Entity()
        root.name = "Environment"
        guard let tex = texture(kind) else { return root }
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white, texture: .init(tex))
        let mesh: MeshResource?
        switch coverage {
        case .full360:
            mesh = patch(radius: 40, azSpan: 360, elMin: -90, elMax: 90, azSteps: 160, elSteps: 80)
        case .arc180:
            mesh = patch(radius: 14, azSpan: 180, elMin: -7, elMax: 62, azSteps: 72, elSteps: 24)
        case .window60:
            mesh = patch(radius: 6, azSpan: 60, elMin: -4, elMax: 26, azSteps: 24, elSteps: 10)
        }
        if let mesh {
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.name = "Backdrop"
            e.position = [0, 1.45, 0]   // centred near eye height
            root.addChild(e)
        }
        if coverage == .full360, let gmesh = groundFromPanorama(radius: 30) {
            // Virtual ground at the real floor height, painted from the same 360° scene (seen from eye height),
            // so the floor continues the landscape instead of being a flat colour.
            var gm = UnlitMaterial()
            gm.color = .init(tint: .white, texture: .init(tex))
            let ground = ModelEntity(mesh: gmesh, materials: [gm])
            ground.name = "VirtualFloor"
            ground.position.y = -0.003
            root.addChild(ground)
            // Up close the photographed ground is stretched and soft, so the person stands on real, lit grass
            // (Poly Haven "Leafy Grass", CC0) that fades out into the photograph between 6 and 14 m.
            addNearGround(to: root, kind: kind)
            // Light the grass (and the coach, see `sceneLight`) with the scene's own panorama.
            addSceneLight(to: root, kind: kind)
        }
        if coverage == .full360 && kind == .auroraNight {
            // lantern festival: warm sky lanterns hanging in the distance (still, so nothing moves around the person)
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<46 {
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                let r = Float.random(in: 7...22, using: &rng)
                let l = RhythmStepGame.makeLantern(scale: Float.random(in: 1.4...2.6, using: &rng))
                l.position = [sin(a) * r, Float.random(in: 3.0...11.0, using: &rng), -cos(a) * r]
                root.addChild(l)
            }
        }
        if coverage != .full360 {
            // soft frame line that marks the edge of the virtual view
            root.addChild(frameGlow(coverage: coverage))
        }
        return root
    }

    /// Floor disc whose UVs look up the equirectangular painting along the ray from eye height,
    /// matching `patch` (u 0.5 = ahead, v from elevation).
    static func groundFromPanorama(radius: Float, eye: Float = 1.6, rings: Int = 48, azSteps: Int = 96) -> MeshResource? {
        var pos: [SIMD3<Float>] = []; var uv: [SIMD2<Float>] = []; var nrm: [SIMD3<Float>] = []
        for i in 0...rings {
            // denser rings near the person
            let t = Float(i) / Float(rings)
            let r = max(0.01, radius * t * t)
            for j in 0...azSteps {
                let az = -Float.pi + 2 * Float.pi * Float(j) / Float(azSteps)
                let p = SIMD3<Float>(sin(az) * r, 0, -cos(az) * r)
                let d = p - SIMD3<Float>(0, eye, 0)
                let el = asin(d.y / simd_length(d))
                pos.append(p); nrm.append([0, 1, 0])
                uv.append([0.5 + az / (2 * .pi), 0.5 + el / .pi])
            }
        }
        var idx: [UInt32] = []
        let w = UInt32(azSteps + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(azSteps) {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                idx += [a, b, c, b, d, c, a, c, b, b, c, d]
            }
        }
        var desc = MeshDescriptor(name: "ground")
        desc.positions = MeshBuffers.Positions(pos)
        desc.normals = MeshBuffers.Normals(nrm)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }

    /// Spherical patch centred straight ahead (-Z). UVs follow the equirectangular painting (u 0.5 = ahead).
    /// `imageElMin`: the lowest elevation the (possibly cropped) panorama covers; -90 for a full equirectangular image.
    /// Cropping skies to the band that is actually visible keeps their resolution high and their memory low.
    static func patch(radius r: Float, azSpan: Float, elMin: Float, elMax: Float, azSteps: Int, elSteps: Int, imageElMin: Float = -90) -> MeshResource? {
        var pos: [SIMD3<Float>] = []; var uv: [SIMD2<Float>] = []; var nrm: [SIMD3<Float>] = []
        for i in 0...elSteps {
            let el = (elMin + (elMax - elMin) * Float(i) / Float(elSteps)) * .pi / 180
            for j in 0...azSteps {
                let az = (-azSpan / 2 + azSpan * Float(j) / Float(azSteps)) * .pi / 180
                let d = SIMD3<Float>(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
                pos.append(d * r)
                nrm.append(-d)
                let elDeg = el * 180 / .pi
                uv.append([0.5 + az / (2 * .pi), (elDeg - imageElMin) / (90 - imageElMin)])
            }
        }
        var idx: [UInt32] = []
        let w = UInt32(azSteps + 1)
        for i in 0..<UInt32(elSteps) {
            for j in 0..<UInt32(azSteps) {
                let a = i * w + j, b = a + 1, c = a + w, d = c + 1
                // both windings so it renders from inside regardless of culling convention
                idx += [a, b, c, b, d, c]
                idx += [a, c, b, b, c, d]
            }
        }
        var desc = MeshDescriptor(name: "patch")
        desc.positions = MeshBuffers.Positions(pos)
        desc.normals = MeshBuffers.Normals(nrm)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }

    // MARK: Near ground and scene light (full immersion)

    private static var grassMaterialCache: [EnvironmentKind: PhysicallyBasedMaterial] = [:]

    private static func grassMaterial(_ kind: EnvironmentKind, tiles: Float) -> PhysicallyBasedMaterial? {
        guard let u = Bundle.main.url(forResource: "tex_leafy_grass", withExtension: "jpg")
                ?? Bundle.main.url(forResource: "tex_grass", withExtension: "jpg"),
              let t = try? TextureResource.load(contentsOf: u) else { return nil }
        var m = PhysicallyBasedMaterial()
        // each scene's grass takes on its light: warm meadow, cool dawn shores, deep blue night
        let tint: UIColor
        switch kind.flavor {
        case .goldenMeadow: tint = UIColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1)
        case .dawnLake: tint = UIColor(red: 0.86, green: 0.9, blue: 0.95, alpha: 1)
        case .riverValley: tint = UIColor(red: 0.92, green: 0.95, blue: 0.88, alpha: 1)
        case .auroraNight: tint = UIColor(red: 0.42, green: 0.5, blue: 0.62, alpha: 1)
        }
        let d = MTLSamplerDescriptor()
        d.sAddressMode = .repeat; d.tAddressMode = .repeat
        d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear
        d.maxAnisotropy = 8
        m.baseColor = .init(tint: tint, texture: .init(t, sampler: .init(d)))
        m.roughness = .init(floatLiteral: 0.95)
        m.textureCoordinateTransform = .init(offset: .zero, scale: [tiles, tiles], rotation: 0)
        return m
    }

    /// A grass disc around the person, then rings of falling opacity, so it melts into the photographed ground.
    private static func addNearGround(to root: Entity, kind: EnvironmentKind) {
        let inner: Float = 6, outer: Float = 14, rings = 8
        guard var mat = grassMaterial(kind, tiles: 1) else { return }
        // UVs of the generated meshes span the whole shape, so tile by size (about one tile per 1.2 m)
        var disc = mat; disc.textureCoordinateTransform = .init(offset: .zero, scale: [inner * 2 / 1.2, inner * 2 / 1.2], rotation: 0)
        let d = ModelEntity(mesh: .generatePlane(width: inner * 2, depth: inner * 2, cornerRadius: inner), materials: [disc])
        d.name = "NearGround"; d.position.y = 0.002
        root.addChild(d)
        for i in 0..<rings {
            let r0 = inner + (outer - inner) * Float(i) / Float(rings)
            let r1 = inner + (outer - inner) * Float(i + 1) / Float(rings)
            guard let ring = annulus(inner: r0, outer: r1, segments: 96) else { continue }
            mat = grassMaterial(kind, tiles: 1) ?? mat
            mat.textureCoordinateTransform = .init(offset: .zero, scale: [r1 * 2 / 1.2, r1 * 2 / 1.2], rotation: 0)
            mat.blending = .transparent(opacity: .init(floatLiteral: 1 - (Float(i) + 0.5) / Float(rings)))
            let e = ModelEntity(mesh: ring, materials: [mat]); e.position.y = 0.002
            root.addChild(e)
        }
    }

    /// Image-based light from the scene's panorama, named "SceneLight" so the session can light the coach with it.
    private static func addSceneLight(to root: Entity, kind: EnvironmentKind) {
        guard let u = Bundle.main.url(forResource: kind.imageName, withExtension: "jpg") else { return }
        Task { @MainActor in
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                  let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                         kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
                  let env = try? await EnvironmentResource(equirectangular: img) else { return }
            let light = Entity(); light.name = "SceneLight"
            light.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.7))
            root.addChild(light)
            for c in root.children where c.name == "NearGround" || c is ModelEntity {
                c.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
        }
    }

    private static func frameGlow(coverage: EnvironmentCoverage) -> Entity {
        let e = Entity()
        let span = coverage.degrees
        let r: Float = coverage == .arc180 ? 13.9 : 5.95
        let elMin: Float = coverage == .arc180 ? -7 : -4
        let elMax: Float = coverage == .arc180 ? 62 : 26
        var m = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let steps = 40
        for k in 0...steps {
            let az = (-span / 2 + span * Float(k) / Float(steps)) * .pi / 180
            for el in [elMin, elMax] {
                let er = el * .pi / 180
                let d = SIMD3<Float>(sin(az) * cos(er), sin(er), -cos(az) * cos(er))
                let s = ModelEntity(mesh: .generateSphere(radius: coverage == .arc180 ? 0.05 : 0.02), materials: [m])
                s.position = d * r + [0, 1.45, 0]
                e.addChild(s)
            }
        }
        return e
    }

    /// Flat ring on the floor (safe-zone marker, game pads).
    static func annulus(inner: Float, outer: Float, segments: Int = 64) -> MeshResource? {
        var pos: [SIMD3<Float>] = []; var nrm: [SIMD3<Float>] = []; var idx: [UInt32] = []; var uv: [SIMD2<Float>] = []
        for k in 0...segments {
            let a = Float(k) / Float(segments) * 2 * .pi
            pos.append([cos(a) * inner, 0, sin(a) * inner]); pos.append([cos(a) * outer, 0, sin(a) * outer])
            nrm.append([0, 1, 0]); nrm.append([0, 1, 0])
            // planar UVs over the outer square, so textures tile the same way as on a plane of that size
            uv.append([cos(a) * inner / outer * 0.5 + 0.5, sin(a) * inner / outer * 0.5 + 0.5])
            uv.append([cos(a) * 0.5 + 0.5, sin(a) * 0.5 + 0.5])
        }
        for k in 0..<UInt32(segments) {
            let a = k * 2, b = a + 1, c = a + 2, d = a + 3
            idx += [a, c, b, b, c, d, a, b, c, b, d, c]
        }
        var desc = MeshDescriptor(name: "ring")
        desc.positions = MeshBuffers.Positions(pos)
        desc.normals = MeshBuffers.Normals(nrm)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        desc.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [desc])
    }

    static func glow(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial(color: color)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    /// Safe-zone ring around the person's starting position.
    static func safeZone(radius: Float = 0.9) -> Entity {
        let e = Entity(); e.name = "SafeZone"
        if let mesh = annulus(inner: radius - 0.025, outer: radius) {
            let ring = ModelEntity(mesh: mesh, materials: [glow(UIColor(red: 0.4, green: 0.9, blue: 1, alpha: 1), opacity: 0.6)])
            ring.position.y = 0.004
            e.addChild(ring)
        }
        return e
    }
}

extension UIColor {
    func lighter(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r + amount), green: min(1, g + amount), blue: min(1, b + amount), alpha: a)
    }
}
