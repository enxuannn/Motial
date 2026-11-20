import AVFoundation
import Foundation
import Observation

/// The sound of the drive: an engine hum whose pitch and volume follow your speed (so you can hear the pedal),
/// wind that grows with speed, and short cues for "go", gates, slides and laps. All sounds are generated for
/// Motial (no licensed samples, Tools/AssetPipeline/make_sfx.py) and kept soft: this is rehab, not an arcade.
@MainActor
final class DriveAudio {
    private var engine: AVAudioPlayer?
    private var wind: AVAudioPlayer?
    private var road: AVAudioPlayer?
    private let loudness: Float

    /// loudness: 1 for the first-person cockpit, lower for the small tabletop car
    init(loudness: Float = 1) { self.loudness = loudness }

    /// goCue: false when the game runs its own start-light countdown
    func start(goCue: Bool = true) {
        engine = Self.loop("sfx_engine_loop")
        wind = Self.loop("amb_wind_loop")
        road = Self.loop("amb_road_loop")          // tyre and road roar, under the engine
        if goCue { SoundManager.shared.play("sfx_count_go", volume: 0.6) }
    }

    /// speed01: 0 stopped … 1 top speed
    func update(speed01: Float) {
        let s = max(0, min(1, speed01))
        let fx = SoundManager.shared.effectsVolume
        engine?.rate = 0.65 + 0.95 * s
        engine?.volume = (0.08 + 0.32 * s) * fx * loudness
        wind?.volume = 0.32 * s * s * fx * loudness
        road?.rate = 0.8 + 0.5 * s
        road?.volume = (0.04 + 0.22 * s) * fx * loudness
    }

    /// Pause and resume with the session (STOP / pause), so the engine never hums over a paused screen.
    func setPaused(_ paused: Bool) {
        for p in [engine, wind, road] { if paused { p?.pause() } else { p?.play() } }
    }

    func stop() {
        for p in [engine, wind, road] {
            p?.setVolume(0, fadeDuration: 0.8)
            let q = p
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { q?.stop() }
        }
        engine = nil; wind = nil; road = nil
    }

    private static func loop(_ name: String) -> AVAudioPlayer? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "wav") ?? Bundle.main.url(forResource: name, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: u) else { return nil }
        p.enableRate = true
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        return p
    }
}

// MARK: - Records of past drives

/// One finished (or stopped) pedal-game run, kept on this device for the Progress dashboard.
struct GameRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    let exerciseID: String
    let title: String
    let seconds: Double
    let orbs: Int
    let obstaclesCleared: Int        // clean corners / smooth gates / lanterns lit
    let obstaclesTotal: Int
    let obstacleName: String         // "corners", "gates", "lanterns"
    let bestLap: Double?
    let smoothness: Double           // 0…1
    let completed: Bool
}

/// What a game reports when it ends.
struct GameSummary {
    let orbs: Int
    let cleared: Int
    let total: Int
    let obstacleName: String
    let bestLap: Double?
    let smoothness: Double
    let completed: Bool
}

@MainActor
@Observable
final class GameLog {
    static let shared = GameLog()
    private(set) var records: [GameRecord] = []

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("game_records.json")
    }

    private init() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: Self.url), let r = try? dec.decode([GameRecord].self, from: d) { records = r }
    }

    func add(_ r: GameRecord) {
        records.append(r)
        if records.count > 500 { records.removeFirst(records.count - 500) }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(records) { try? d.write(to: Self.url, options: [.atomic, .completeFileProtection]) }
    }

    func eraseAll() {
        records = []
        try? FileManager.default.removeItem(at: Self.url)
    }
}
