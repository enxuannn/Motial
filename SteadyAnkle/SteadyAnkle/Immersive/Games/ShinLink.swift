import Foundation
import Network
import Observation

/// Receives ankle movement from the "Motial Pedal" iPhone companion over the local network (Bonjour + TCP).
/// The phone is strapped to the top of the foot and sends one line per frame:
///   "v=0.423 a=1"   v = how far the toes point down, 0 (resting) … 1 (full range); a = 1 real sensor, 0 practice slider
/// Vision Pro answers with short status lines ("s=Lanterns 3 of 8") that the phone shows.
/// Nothing leaves the local network and nothing is stored.
@MainActor
@Observable
final class ShinLink {
    static let shared = ShinLink()
    static let serviceType = "_steadyshin._tcp"

    private(set) var value: Float = 0
    private(set) var realSensor = false
    private(set) var lastUpdate = Date.distantPast
    private(set) var listening = false
    private(set) var phoneName: String?

    /// A phone has sent movement within the last 1.5 s.
    var connected: Bool { Date().timeIntervalSince(lastUpdate) < 1.5 }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private let queue = DispatchQueue(label: "sg.steady.shinlink")
    @ObservationIgnored private var lastStatus = ""

    private init() {}

    /// Starts advertising "Motial" on the local network (first use shows the local-network permission).
    func start() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: "Motial", type: Self.serviceType)
            l.newConnectionHandler = { [weak self] c in
                Task { @MainActor in self?.accept(c) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.listening = true
                    case .failed(let e):
                        print("[Steady] shin link failed: \(e)")
                        self.listening = false
                        self.listener?.cancel(); self.listener = nil
                    case .cancelled: self.listening = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
            print("[Steady] shin link: advertising \(Self.serviceType)")
        } catch {
            print("[Steady] shin link could not start: \(error)")
        }
    }

    func stop() {
        connection?.cancel(); connection = nil
        listener?.cancel(); listener = nil
        listening = false
    }

    /// Sends a short status line to the phone (only when it changed).
    func sendStatus(_ text: String) {
        guard text != lastStatus, let c = connection else { return }
        lastStatus = text
        c.send(content: Data("s=\(text)\n".utf8), completion: .contentProcessed { _ in })
    }

    private func accept(_ c: NWConnection) {
        connection?.cancel()
        connection = c
        buffer.removeAll()
        lastStatus = ""
        if case .service(let name, _, _, _) = c.endpoint { phoneName = name }
        c.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in if self?.connection === c { self?.connection = nil } } }
        }
        c.start(queue: queue)
        receive(on: c)
        print("[Steady] shin link: phone connected")
    }

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty { self.consume(data) }
                if done || error != nil {
                    if self.connection === c { self.connection = nil }
                    c.cancel()
                    return
                }
                self.receive(on: c)
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            var v: Float?
            var a = false
            for part in line.split(separator: " ") {
                let kv = part.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                if kv[0] == "v" { v = Float(kv[1]) }
                if kv[0] == "a" { a = kv[1] == "1" }
                if kv[0] == "n" { phoneName = String(kv[1]).replacingOccurrences(of: "_", with: " ") }
            }
            if let v {
                value = max(0, min(1, v))
                realSensor = a
                lastUpdate = Date()
            }
        }
        if buffer.count > 8192 { buffer.removeAll() }
    }
}
