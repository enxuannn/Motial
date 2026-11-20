import AVFoundation

/// Lightweight tempo estimation for songs the person imports (energy-flux onset envelope + autocorrelation).
enum BeatDetector {
    struct Result { let bpm: Double; let firstBeat: Double }

    static func analyze(url: URL, maxSeconds: Double = 90) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(min(Double(file.length), sr * maxSeconds))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do { try file.read(into: buf, frameCount: frames) } catch { return nil }
        guard let ch = buf.floatChannelData else { return nil }
        let n = Int(buf.frameLength)
        let channels = Int(format.channelCount)
        let hop = Int(sr / 100)              // 100 Hz envelope
        let count = n / hop
        guard count > 400 else { return nil }
        var energy = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var e: Float = 0
            let s = i * hop
            for j in 0..<hop {
                var v: Float = 0
                for c in 0..<channels { v += ch[c][s + j] }
                e += v * v
            }
            energy[i] = sqrt(e / Float(hop))
        }
        // positive energy flux = onset strength
        var flux = [Float](repeating: 0, count: count)
        for i in 1..<count { flux[i] = max(0, energy[i] - energy[i - 1]) }
        let mean = flux.reduce(0, +) / Float(count)
        for i in 0..<count { flux[i] = max(0, flux[i] - mean) }
        // autocorrelation over 70 – 180 BPM
        var bestLag = 0; var bestScore: Float = 0
        let minLag = Int(100.0 * 60.0 / 180.0), maxLag = Int(100.0 * 60.0 / 70.0)
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in lag..<count { s += flux[i] * flux[i - lag] }
            // gentle preference for tempos around 100 – 125 BPM
            let bpm = 6000.0 / Float(lag)
            let w = exp(-pow((bpm - 112) / 60, 2))
            s *= (0.7 + 0.3 * w)
            if s > bestScore { bestScore = s; bestLag = lag }
        }
        guard bestLag > 0 else { return nil }
        // phase: which offset within one beat period collects most onset energy
        var bestPhase = 0; var bestPhaseScore: Float = 0
        for p in 0..<bestLag {
            var s: Float = 0; var i = p
            while i < count { s += flux[i]; i += bestLag }
            if s > bestPhaseScore { bestPhaseScore = s; bestPhase = p }
        }
        return Result(bpm: 6000.0 / Double(bestLag), firstBeat: Double(bestPhase) / 100.0)
    }
}
