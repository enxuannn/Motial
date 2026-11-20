import AVFoundation
import RealityKit
import CryptoKit

/// Music, ambience, UI sound effects and the spoken coach.
/// Spatial (3D-positioned) effects are played through RealityKit on the entity that makes the sound.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var ambience: AVAudioPlayer?
    private(set) var music: AVAudioPlayer?
    private var sfx: [String: AVAudioPlayer] = [:]
    private var spatial: [String: AudioFileResource] = [:]
    private let speech = AVSpeechSynthesizer()
    var voiceEnabled = true
    var effectsVolume: Float = 0.8
    var musicVolume: Float = 0.55

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for n in ["sfx_tick", "sfx_catch", "sfx_mitt", "sfx_pitch", "sfx_stone", "sfx_splash"] { preloadSpatial(n) }
    }

    func apply(_ s: AppSettings) {
        voiceEnabled = s.voiceCoach
        effectsVolume = Float(s.effectsVolume)
        musicVolume = s.music ? Float(s.musicVolume) : 0
        music?.volume = musicVolume
        ambience?.volume = musicVolume * 0.7
    }

    private func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav") ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    // MARK: Effects
    func play(_ name: String, volume: Float = 1) {
        let player: AVAudioPlayer
        if let p = sfx[name] { player = p } else {
            guard let u = url(name), let p = try? AVAudioPlayer(contentsOf: u) else { return }
            p.prepareToPlay(); sfx[name] = p; player = p
        }
        player.volume = effectsVolume * volume
        player.currentTime = 0
        player.play()
    }

    /// 3D sound emitted from an entity (head-tracked spatial audio).
    /// Resources load asynchronously on visionOS; the first use plays the plain effect while the spatial one loads.
    func playSpatial(_ name: String, on entity: Entity, gain: Double = 0) {
        guard let res = spatial[name] else {
            play(name)
            preloadSpatial(name)
            return
        }
        if entity.components[SpatialAudioComponent.self] == nil {
            entity.components.set(SpatialAudioComponent(gain: gain))
        }
        entity.playAudio(res)
    }

    private var loading: Set<String> = []
    func preloadSpatial(_ name: String) {
        guard spatial[name] == nil, !loading.contains(name) else { return }
        loading.insert(name)
        let file = Bundle.main.url(forResource: name, withExtension: "wav") != nil ? "\(name).wav" : "\(name).m4a"
        Task { @MainActor in
            var cfg = AudioFileResource.Configuration()
            cfg.shouldLoop = false
            if let r = try? await AudioFileResource(named: file, in: .main, configuration: cfg) { self.spatial[name] = r }
            self.loading.remove(name)
        }
    }

    // MARK: Ambience & music
    func startAmbience(_ name: String) {
        guard ambience?.url?.deletingPathExtension().lastPathComponent != name else { return }
        ambience?.stop()
        guard let u = url(name), let p = try? AVAudioPlayer(contentsOf: u) else { return }
        p.numberOfLoops = -1; p.volume = 0; p.play()
        p.setVolume(musicVolume * 0.7, fadeDuration: 2.0)
        ambience = p
    }
    func stopAmbience() {
        ambience?.setVolume(0, fadeDuration: 1.0)
        let a = ambience
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { a?.stop() }
        ambience = nil
    }
    @discardableResult
    func playMusic(url u: URL, loop: Bool = true) -> AVAudioPlayer? {
        music?.stop()
        guard let p = try? AVAudioPlayer(contentsOf: u) else { return nil }
        p.numberOfLoops = loop ? -1 : 0
        p.volume = musicVolume
        p.prepareToPlay(); p.play()
        music = p
        ambience?.setVolume(musicVolume * 0.25, fadeDuration: 1.0)
        return p
    }
    func playMusic(named name: String) -> AVAudioPlayer? {
        guard let u = url(name) else { return nil }
        return playMusic(url: u)
    }
    func stopMusic() {
        music?.setVolume(0, fadeDuration: 0.6)
        let m = music
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { m?.stop() }
        music = nil
        ambience?.setVolume(musicVolume * 0.7, fadeDuration: 1.0)
    }

    // MARK: Voice coach
    // A warm neural voice (Kokoro "Heart", pre-rendered clips in Resources/Voice: vo_<key>.m4a) for every fixed
    // sentence, including composites with numbers. There is no robotic fallback.
    private enum VoiceItem { case clip(URL), tts(String) }
    private var voiceQueue: [VoiceItem] = []
    private var voicePlayer: AVAudioPlayer?
    private lazy var voiceDelegate = VoiceDelegate { [weak self] in self?.playNextVoice() }
    private var speaking: Bool { (voicePlayer?.isPlaying ?? false) || speech.isSpeaking }
    /// True while a voice line is playing (drives the coach's talking animation).
    var isVoicePlaying: Bool { speaking || !voiceQueue.isEmpty }

    func say(_ text: String, rate: Float = 0.47, interrupt: Bool = false) {
        guard voiceEnabled, !text.isEmpty else { return }
        if interrupt { stopVoice() }
        for sentence in Self.sentences(text) {
            // One voice only: the warm human-sounding clips. A sentence without a clip is shown on screen
            // (every spoken line also appears as text) but never read by the robotic system voice.
            if let u = Bundle.main.url(forResource: "vo_" + Self.voiceKey(sentence), withExtension: "m4a") {
                voiceQueue.append(.clip(u))
            } else {
                #if DEBUG
                print("[Motial] voice clip missing: \(sentence)")
                #endif
            }
        }
        if !speaking { playNextVoice() }
    }

    private func playNextVoice() {
        guard !voiceQueue.isEmpty else { return }
        switch voiceQueue.removeFirst() {
        case .clip(let u):
            guard let p = try? AVAudioPlayer(contentsOf: u) else { playNextVoice(); return }
            p.delegate = voiceDelegate
            p.volume = 1
            p.prepareToPlay(); p.play()
            voicePlayer = p
        case .tts(let t):
            speech.delegate = voiceDelegate
            let u = AVSpeechUtterance(string: t)
            u.rate = 0.45
            u.pitchMultiplier = 1.05
            u.postUtteranceDelay = 0.12
            u.voice = Self.bestVoice
            speech.speak(u)
        }
    }

    func stopVoice() {
        voiceQueue.removeAll()
        voicePlayer?.stop(); voicePlayer = nil
        speech.stopSpeaking(at: .immediate)
    }

    /// Premium / enhanced English voices sound far more natural than the default one.
    private static let bestVoice: AVSpeechSynthesisVoice? = {
        let en = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let preferred = ["Zoe", "Ava", "Samantha", "Serena", "Karen", "Moira"]
        let ranked = en.sorted { a, b in
            if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
            let ia = preferred.firstIndex(of: a.name) ?? 99, ib = preferred.firstIndex(of: b.name) ?? 99
            return ia < ib
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// Same rule as Tools/AssetPipeline/make_voice.py: lowercase, straight quotes, single spaces, no final . ! ?
    static func voiceKey(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        while let last = t.last, ".!?".contains(last) { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespaces)
        let digest = Insecure.SHA1.hash(data: Data(t.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []; var cur = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            cur.append(ch)
            if ".!?".contains(ch) && (i + 1 == chars.count || chars[i + 1].isWhitespace) {
                let t = cur.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { out.append(t) }; cur = ""
            }
        }
        let t = cur.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { out.append(t) }
        return out
    }

    func stopAll() {
        stopVoice(); stopMusic(); stopAmbience()
        sfx.values.forEach { $0.stop() }
    }
}


/// Calls back when a voice clip or a spoken sentence finishes, so the next one starts.
final class VoiceDelegate: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    let next: @MainActor () -> Void
    init(next: @escaping @MainActor () -> Void) { self.next = next }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.next() } }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.next() } }
    }
}
