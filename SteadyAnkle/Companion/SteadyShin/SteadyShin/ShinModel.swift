import Foundation
import CoreMotion
import Network
import Observation
import UIKit
import simd

/// Reads how far the toes point down from the phone's tilt and streams it to Steady on Vision Pro.
///
/// The phone sits on the top of the foot (any orientation). When the toes point down the foot tilts, so the
/// phone tilts with it; the shin barely moves in this exercise, so the foot is the place to measure.
///
/// "Set resting position" stores the gravity direction with the foot relaxed, "Set full range" stores it with the
/// toes pointed down as far as is comfortable. Movement is the projection of the current tilt onto that path,
/// so 0 = resting and 1 = full comfortable range. Without a range it uses 20° of tilt as full.
@MainActor
@Observable
final class ShinModel {
    enum Link: Equatable { case searching, connecting, connected, waiting(String) }

    static let serviceType = "_steadyshin._tcp"
    /// One model for the whole app, so Siri / Shortcuts (App Intents) act on the same pedal the screen shows.
    static let shared = ShinModel()

    var link: Link = .searching
    var visionName: String?
    private(set) var sensorValue: Double = 0
    var practice: Double = 0              // slider, for the Simulator or to try it without strapping the phone on
    var usePractice = false
    private(set) var sensorAvailable = false
    private(set) var hasRest = false
    private(set) var hasRange = false
    private(set) var status: String?      // from Vision Pro, e.g. "Lanterns 3 of 8"
    private(set) var rangeDegrees: Double = 20

    var value: Double { (usePractice || !sensorAvailable) ? practice : sensorValue }

    /// What the ankle is doing right now (for the "What's working" learning card).
    enum Motion { case resting, pushing, easing, holding }
    private(set) var ankleMotion: Motion = .resting
    @ObservationIgnored private var lastValue: Double = 0
    @ObservationIgnored private var velocity: Double = 0

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var gravity = SIMD3<Double>(0, -1, 0)
    @ObservationIgnored private var rest: SIMD3<Double>?
    @ObservationIgnored private var full: SIMD3<Double>?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var results: [NWBrowser.Result] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private let queue = DispatchQueue(label: "sg.steady.shin.net")
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true     // the phone is strapped on: keep it awake
        sensorAvailable = motion.isDeviceMotionAvailable
        if sensorAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
                MainActor.assumeIsolated {
                    guard let self, let m else { return }
                    let g = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
                    self.gravity = g
                    if self.rest == nil { self.rest = g }
                    self.sensorValue = self.position(of: g)
                }
            }
        } else {
            usePractice = true
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send() }
        }
        browse()
    }

    // MARK: Calibration
    func setRest() {
        rest = gravity
        hasRest = true
        if let f = full { rangeDegrees = angle(gravity, f) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func setFullRange() {
        if rest == nil { rest = gravity }
        full = gravity
        hasRange = true
        rangeDegrees = angle(rest!, gravity)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func resetCalibration() {
        rest = gravity; full = nil
        hasRest = false; hasRange = false; rangeDegrees = 20
    }

    private func position(of g: SIMD3<Double>) -> Double {
        guard let r = rest else { return 0 }
        if let f = full {
            let d = f - r
            let l2 = simd_length_squared(d)
            if l2 > 1e-4 { return max(0, min(1, simd_dot(g - r, d) / l2)) }
        }
        return max(0, min(1, angle(g, r) / 20))
    }

    private func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let c = simd_dot(simd_normalize(a), simd_normalize(b))
        return acos(max(-1, min(1, c))) * 180 / .pi
    }

    // MARK: Network (Bonjour on the local network)
    private func browse() {
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] found, _ in
            Task { @MainActor in self?.update(found) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed(let e):
                    self.link = .waiting("Local network blocked (\(e.localizedDescription)). Allow it in Settings › Privacy › Local Network.")
                    self.browser?.cancel(); self.browser = nil
                    try? await Task.sleep(for: .seconds(3))
                    self.browse()
                case .waiting(let e):
                    self.link = .waiting("Allow local network access so Motial Pedal can find your Vision Pro. (\(e.localizedDescription))")
                default: break
                }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    private func update(_ found: Set<NWBrowser.Result>) {
        results = Array(found)
        if connection == nil { connectToFirst() }
    }

    private func connectToFirst() {
        guard let r = results.first else { link = .searching; visionName = nil; return }
        if case .service(let name, _, _, _) = r.endpoint { visionName = name }
        let c = NWConnection(to: r.endpoint, using: .tcp)
        connection = c
        link = .connecting
        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                switch state {
                case .ready:
                    self.link = .connected
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.receive(on: c)
                case .failed, .cancelled:
                    self.connection = nil
                    self.status = nil
                    self.link = .searching
                    try? await Task.sleep(for: .seconds(1))
                    if self.connection == nil { self.connectToFirst() }
                default: break
                }
            }
        }
        c.start(queue: queue)
    }

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.connection === c else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    while let nl = self.buffer.firstIndex(of: 0x0A) {
                        let line = String(decoding: self.buffer[self.buffer.startIndex..<nl], as: UTF8.self)
                        self.buffer.removeSubrange(self.buffer.startIndex...nl)
                        if line.hasPrefix("s=") { self.status = String(line.dropFirst(2)) }
                    }
                }
                if done || error != nil { c.cancel(); return }
                self.receive(on: c)
            }
        }
    }

    private func send() {
        // learning state from the pedal movement (≈ 30 Hz)
        let v = value
        velocity += ((v - lastValue) * 30 - velocity) * 0.25
        lastValue = v
        let m: Motion = velocity > 0.25 ? .pushing : (velocity < -0.12 && v > 0.04 ? .easing : (v > 0.3 ? .holding : .resting))
        if m != ankleMotion { ankleMotion = m }
        guard let c = connection, link == .connected else { return }
        let name = UIDevice.current.name.replacingOccurrences(of: " ", with: "_")
        let line = String(format: "v=%.3f a=%d n=%@\n", value, (usePractice || !sensorAvailable) ? 0 : 1, name)
        c.send(content: Data(line.utf8), completion: .contentProcessed { _ in })
    }
}
