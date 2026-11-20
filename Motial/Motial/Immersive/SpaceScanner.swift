import ARKit
import RealityKit
import simd

/// Safety calibration before standing exercises: the person slowly looks all the way around while
/// ARKit plane detection finds the floor, walls, tables and seats. Steady then reports the nearest
/// obstacle so the person can clear a safe area (about 1 m in every direction, more for stepping games).
/// Falls back to a guided look-around plus checklist where plane detection isn't available (e.g. Simulator).
@MainActor
@Observable
final class SpaceScanner {
    struct Obstacle: Equatable { let label: String; let distance: Float }
    enum State: Equatable { case idle, scanning, done }

    private(set) var state: State = .idle
    private(set) var coverage: Double = 0            // 0…1 share of the 360° look-around completed
    private(set) var floorFound = false
    private(set) var nearest: Obstacle?
    private(set) var supported = PlaneDetectionProvider.isSupported

    /// Clear radius we ask for around the person (metres).
    var requiredClearance: Float = 1.0

    private let session = ARKitSession()
    private let planes = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
    @ObservationIgnored private var anchors: [UUID: PlaneAnchor] = [:]
    @ObservationIgnored private var bins = Set<Int>()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var centre = SIMD3<Float>(0, 0, 0)

    var isSafe: Bool { state == .done && (nearest.map { $0.distance >= requiredClearance } ?? true) }

    var summary: String {
        guard state == .done else { return "" }
        if !supported { return "Look-around complete. Please double-check the floor around you is clear." }
        if let n = nearest, n.distance < requiredClearance {
            return String(format: "%@ about %.1f m away. Move it, or step to a clearer spot, then scan again.", n.label, n.distance)
        }
        return String(format: "Your space looks clear (at least %.1f m around you).", requiredClearance)
    }

    func start(centre c: SIMD3<Float>) async {
        centre = c
        coverage = 0; bins.removeAll(); nearest = nil; floorFound = false
        state = .scanning
        guard supported else { return }
        let auth = await session.requestAuthorization(for: [.worldSensing])
        guard auth[.worldSensing] == .allowed else { supported = false; return }
        do { try await session.run([planes]) } catch { supported = false; return }
        task = Task { @MainActor in
            for await update in planes.anchorUpdates {
                switch update.event {
                case .added, .updated: anchors[update.anchor.id] = update.anchor
                case .removed: anchors[update.anchor.id] = nil
                }
                evaluate()
            }
        }
    }

    /// Feed the current head direction every frame while scanning.
    func update(headForward f: SIMD3<Float>, head: SIMD3<Float>) {
        guard state == .scanning else { return }
        centre = SIMD3<Float>(head.x, 0, head.z)
        let yaw = atan2(f.x, -f.z)                       // −π…π
        let bin = Int(((yaw + .pi) / (2 * .pi)) * 12) % 12
        bins.insert(bin)
        coverage = Double(bins.count) / 12
        if coverage >= 0.99 { finish() }
    }

    func finish() {
        guard state == .scanning else { return }
        evaluate()
        state = .done
    }

    func stop() {
        task?.cancel(); task = nil
        session.stop()
    }

    private func evaluate() {
        var best: Obstacle?
        for a in anchors.values {
            let m = a.originFromAnchorTransform
            let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            if a.classification == .floor { floorFound = true; continue }
            // ignore ceilings and anything above head height
            if a.classification == .ceiling || p.y > 2.0 { continue }
            let half = max(a.geometry.extent.width, a.geometry.extent.height) / 2
            let d = max(0, simd_distance(SIMD2<Float>(p.x, p.z), SIMD2<Float>(centre.x, centre.z)) - half * 0.7)
            let label: String
            switch a.classification {
            case .wall: label = "A wall"
            case .table: label = "A table"
            case .seat: label = "A seat"
            case .door: label = "A door"
            case .window: label = "A window"
            default: label = "Something"
            }
            if best == nil || d < best!.distance { best = Obstacle(label: label, distance: d) }
        }
        nearest = best
    }
}
