import ARKit
import QuartzCore
import simd

/// Head (and, when permitted, hand) tracking used for balance steadiness, rep counting, hop and step detection,
/// and fall-like event detection. All processing is on-device; no camera images are accessed.
@MainActor
final class MotionTracker {
    private let session = ARKitSession()
    private let world = WorldTrackingProvider()
    private var hands: HandTrackingProvider?
    private(set) var running = false
    private(set) var handsAvailable = false

    private(set) var head = SIMD3<Float>(0, 1.6, 0)
    private(set) var headForward = SIMD3<Float>(0, 0, -1)
    private(set) var headVelocity = SIMD3<Float>(0, 0, 0)
    private(set) var leftHand: SIMD3<Float>?
    private(set) var rightHand: SIMD3<Float>?
    /// A landing spot on each hand for Lumi: the centre of the hand, lifted along whichever side faces up (palm or
    /// back of the hand), plus how flat that hand is held (1 = perfectly flat, 0 = vertical).
    private(set) var leftPalm: (spot: SIMD3<Float>, flatness: Float)?
    private(set) var rightPalm: (spot: SIMD3<Float>, flatness: Float)?
    private var lastHead: SIMD3<Float>?
    private var lastTime: TimeInterval = 0

    /// Standing head height captured during calibration.
    var standingHeight: Float = 1.6
    var centre = SIMD3<Float>(0, 0, 0)

    func start() async {
        guard !running else { return }
        var providers: [any DataProvider] = []
        if WorldTrackingProvider.isSupported { providers.append(world) }
        if HandTrackingProvider.isSupported {
            let auth = await session.requestAuthorization(for: [.handTracking])
            if auth[.handTracking] == .allowed {
                let h = HandTrackingProvider(); hands = h; providers.append(h)
            }
        }
        guard !providers.isEmpty else { return }
        do {
            try await session.run(providers)
            running = true
            if let h = hands {
                handsAvailable = true
                Task { await self.consumeHands(h) }
            }
        } catch {
            running = false
        }
    }

    func stop() {
        session.stop()
        running = false
        handsAvailable = false
    }

    private func consumeHands(_ h: HandTrackingProvider) async {
        for await update in h.anchorUpdates {
            let a = update.anchor
            guard a.isTracked, let skel = a.handSkeleton else {
                if a.chirality == .left { leftHand = nil; leftPalm = nil } else { rightHand = nil; rightPalm = nil }
                continue
            }
            func world(_ name: HandSkeleton.JointName) -> SIMD3<Float> {
                let m = a.originFromAnchorTransform * skel.joint(name).anchorFromJointTransform
                return SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            }
            let p = world(.middleFingerKnuckle)
            let wrist = world(.wrist), index = world(.indexFingerKnuckle), little = world(.littleFingerKnuckle)
            let centre = wrist * 0.35 + p * 0.65
            var n = simd_cross(index - little, p - wrist)
            n = simd_length(n) > 1e-5 ? simd_normalize(n) : [0, 1, 0]
            if n.y < 0 { n = -n }                         // whichever side of the hand faces up
            let palm = (spot: centre + n * 0.035, flatness: n.y)
            if a.chirality == .left { leftHand = p; leftPalm = palm } else { rightHand = p; rightPalm = palm }
        }
    }

    /// Call every frame.
    func update() {
        guard running, let anchor = world.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let m = anchor.originFromAnchorTransform
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let f = -SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        let now = CACurrentMediaTime()
        if let lp = lastHead, now > lastTime {
            let v = (p - lp) / Float(now - lastTime)
            headVelocity = headVelocity * 0.6 + v * 0.4
        }
        lastHead = p; lastTime = now
        head = p; headForward = simd_normalize(SIMD3<Float>(f.x, 0, f.z) + SIMD3<Float>(0.0001, 0, 0))
    }

    func calibrate() {
        standingHeight = max(1.0, head.y)
        centre = SIMD3<Float>(head.x, 0, head.z)
    }

    /// A sudden large drop of the head: possible loss of balance or fall.
    func fallLike(hopping: Bool) -> Bool {
        running && (headVelocity.y < (hopping ? -2.4 : -1.4) || head.y < standingHeight * 0.62)
    }
}

/// Steadiness from head sway (root-mean-square horizontal displacement), reported 0 – 100.
/// Experimental training metric — headset sway relates to force-plate sway (Sylcott et al. 2021) but is not a diagnostic test.
struct SwayMeter {
    private var samples: [SIMD2<Float>] = []
    private(set) var touchdowns = 0
    private var lastExcursion = false

    mutating func reset() { samples.removeAll(); touchdowns = 0; lastExcursion = false }

    mutating func add(_ head: SIMD3<Float>) {
        samples.append(SIMD2<Float>(head.x, head.z))
        if samples.count > 90 * 60 { samples.removeFirst(samples.count - 90 * 60) }
        let excursion = currentExcursion > 0.09
        if excursion && !lastExcursion { touchdowns += 1 }
        lastExcursion = excursion
    }

    private var mean: SIMD2<Float> {
        guard !samples.isEmpty else { return .zero }
        return samples.reduce(.zero, +) / Float(samples.count)
    }
    var currentExcursion: Float {
        guard let last = samples.last, samples.count > 30 else { return 0 }
        return simd_length(last - mean)
    }
    /// RMS sway in millimetres.
    var rmsMM: Float {
        guard samples.count > 30 else { return 0 }
        let m = mean
        let s = samples.reduce(Float(0)) { $0 + simd_length_squared($1 - m) }
        return sqrt(s / Float(samples.count)) * 1000
    }
    /// 100 = very steady (≈ 4 mm RMS), 0 = ≈ 40 mm RMS or worse.
    var score: Double {
        guard samples.count > 30 else { return 100 }
        let r = Double(rmsMM)
        return max(0, min(100, 100 - (r - 4) * (100.0 / 36.0)))
    }
    /// Short-window steadiness (last ~1 s) for live feedback.
    var liveSteadiness: Double {
        guard samples.count > 45 else { return 1 }
        let tail = samples.suffix(60)
        let m = tail.reduce(.zero, +) / Float(tail.count)
        let s = tail.reduce(Float(0)) { $0 + simd_length_squared($1 - m) }
        let rms = Double(sqrt(s / Float(tail.count)) * 1000)
        return max(0, min(1, 1 - (rms - 3) / 22))
    }
}

/// Counts repetitions from vertical head motion (heel raises rise ≈ 4–7 cm, mini squats dip ≈ 5–10 cm).
struct HeadRepCounter {
    enum Direction { case up, down }
    let direction: Direction
    var threshold: Float = 0.03
    private var baseline: Float?
    private var inRep = false
    private(set) var count = 0

    init(direction: Direction) { self.direction = direction }

    mutating func reset() { baseline = nil; inRep = false; count = 0 }

    mutating func add(_ y: Float) {
        guard let b = baseline else { baseline = y; return }
        let d = direction == .up ? y - b : b - y
        if !inRep && d > threshold { inRep = true }
        if inRep && d < threshold * 0.35 { inRep = false; count += 1 }
        if !inRep { baseline = b * 0.995 + y * 0.005 }   // slow drift compensation
    }
}

/// Detects hop take-off and landing from head height.
struct HopDetector {
    enum Event { case takeoff, landing(SIMD2<Float>) }
    var baseline: Float = 1.6
    private var airborne = false
    private var peak: Float = 0

    mutating func add(head: SIMD3<Float>, velocityY: Float) -> Event? {
        if !airborne && head.y > baseline + 0.035 && velocityY > 0.3 {
            airborne = true; peak = head.y; return .takeoff
        }
        if airborne {
            peak = max(peak, head.y)
            if head.y < baseline + 0.012 && velocityY < 0.05 {
                airborne = false
                return .landing(SIMD2<Float>(head.x, head.z))
            }
        } else {
            baseline = baseline * 0.998 + head.y * 0.002
        }
        return nil
    }
}
