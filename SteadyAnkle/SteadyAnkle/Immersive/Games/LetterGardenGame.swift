import RealityKit
import UIKit
import simd

/// Ankle Alphabet · Word Garden. The guideline alphabet exercise (draw letters in the air with the big toe, moving
/// from the ankle: JOSPT 2021 early range of motion) turned into a word puzzle.
/// • A large letter board draws each letter stroke by stroke (numbered starts, a glowing tracer, a growing trail); you
///   follow it with your big toe while the coach demonstrates. A badge beside the coach shows the letter being drawn.
/// • The letters spell a mystery word with a clue; part-way through you can tap a guess for bonus points.
/// • Every letter you draw lights up on an A–Z strip, so the whole alphabet (every direction of ankle movement) is
///   collected over the session, as in the original exercise. Calm pace: about 4–5 s per letter, no time pressure.
@MainActor
final class LetterGardenGame: RehabGame {
    let root = Entity()
    private(set) var score = 0
    private(set) var finished = false
    private(set) var feedback: String?
    private var tipText: String?
    var learnTip: String? { tipText }
    var status: String {
        "Word \(min(wordIndex + 1, words.count)) of \(words.count)"      // the board shows the rest
    }
    var guidePoint: SIMD3<Float>? { tracer.isEnabled ? tracer.position(relativeTo: nil) + [0, 0.12, 0] : nil }

    // MARK: Words
    struct Word { let text: String; let clue: String; let decoys: [String]; let cheer: String }
    static let bank: [Word] = [
        Word(text: "CALM", clue: "Clue: how you move today, slow and peaceful.", decoys: ["COOL", "CAKE"], cheer: "Calm muscles heal well."),
        Word(text: "STEP", clue: "Clue: you take one small one at a time.", decoys: ["STAR", "SHIP"], cheer: "One step at a time."),
        Word(text: "HEAL", clue: "Clue: what your ankle is doing right now.", decoys: ["HELP", "HOME"], cheer: "Your ankle is healing every day."),
        Word(text: "WALK", clue: "Clue: a stroll in the park.", decoys: ["WAVE", "WOLF"], cheer: "Every letter brings that walk closer."),
        Word(text: "RISE", clue: "Clue: what the sun does every morning.", decoys: ["RICE", "ROSE"], cheer: "You rise a little stronger each day."),
        Word(text: "GLOW", clue: "Clue: what lanterns do at night.", decoys: ["GRAB", "GOLD"], cheer: "You are glowing today."),
        Word(text: "KITE", clue: "Clue: it flies on a windy day.", decoys: ["KING", "KIND"], cheer: "Light and free, like a kite."),
        Word(text: "VIEW", clue: "Clue: what you see from a hilltop.", decoys: ["VASE", "VOTE"], cheer: "What a view awaits you."),
        Word(text: "JUMP", clue: "Clue: one day, when your physio says yes.", decoys: ["JUICE", "JAZZ"], cheer: "That day is coming."),
        Word(text: "JOY", clue: "Clue: a warm, happy feeling.", decoys: ["JAM", "JAR"], cheer: "Move with joy."),
        Word(text: "SMILE", clue: "Clue: something you do when you feel good.", decoys: ["SLICE", "STONE"], cheer: "Keep smiling, you are doing great."),
        Word(text: "BRAVE", clue: "Clue: coming back after an injury takes this.", decoys: ["BREAD", "BRUSH"], cheer: "Coming back takes courage."),
        Word(text: "DANCE", clue: "Clue: moving to music.", decoys: ["DRINK", "DREAM"], cheer: "You will dance again."),
        Word(text: "BLOOM", clue: "Clue: what flowers do in spring.", decoys: ["BLOCK", "BROOM"], cheer: "You are blooming."),
        Word(text: "HAPPY", clue: "Clue: a big, bright feeling.", decoys: ["HONEY", "HEAVY"], cheer: "Happy ankle, happy you."),
        Word(text: "QUIET", clue: "Clue: a calm, peaceful sound level.", decoys: ["QUEEN", "QUICK"], cheer: "Quiet strength."),
        Word(text: "RELAX", clue: "Clue: let your shoulders drop and do this.", decoys: ["RIVER", "RADIO"], cheer: "Relaxed and in control."),
        Word(text: "ZEBRA", clue: "Clue: a striped animal.", decoys: ["ZEROS", "ZONES"], cheer: "Stripes and all, wonderful."),
        Word(text: "STRONG", clue: "Clue: how your ankle will feel again.", decoys: ["SPRING", "STRING"], cheer: "Stronger every day.")
    ]
    static let praise = ["Beautiful curve.", "Nice and smooth.", "Lovely control.", "Your ankle is waking up.",
                         "That's the way.", "You're doing great.", "Gentle and steady.", "Wonderful.",
                         "Every letter helps it heal.", "Big, smooth letters."]
    /// Letters drawn this session (the A–Z strip) and words already used, so each round brings new ones.
    static var collected = Set<Character>()
    static var used = Set<String>()

    // MARK: State
    private let config: GameConfig
    private var words: [Word] = []
    private var wordIndex = 0
    private var letterIndex = 0
    private var lettersDone = 0
    private enum Phase { case intro, show, trace, yourTurn, reveal, celebrate, done }
    private var phase: Phase = .intro
    private var timer: Float = 0
    private let traceTime: Float
    private var guessOpen = false
    private var guessed = false
    private var praiseCount = 0
    // Your turn: you follow the trainer with your foot. Vision Pro can't see feet, so each letter is confirmed by
    // hand: raise a hand, or look at Done and pinch.
    private let doneButton = Entity()
    private var raisedFor: Float = 0
    private var reminded = false

    // MARK: Scene
    private let board = Entity()
    private let letterRoot = Entity()
    private var segs: [ModelEntity] = []
    private var segAt: [Int] = []                 // path index where each segment ends
    private var path: [(p: SIMD2<Float>, draw: Bool)] = []
    private let tracer = Entity()
    private var clue = Entity()
    private var tiles: [Entity] = []
    private var strip: [Character: ModelEntity] = [:]
    private let badge = Entity()
    private var badgeLetter = Entity()
    private var badgePulse: Float = 0
    private let ring = ModelEntity()
    private var options: [(e: Entity, word: String)] = []
    private let optionRoot = Entity()
    private let sparkles = Sparkles()
    private var boardPos = SIMD3<Float>(0, 1, -1.4)

    static let letterH: Float = 0.4
    static let letterY: Float = -0.02

    init(config: GameConfig) {
        self.config = config
        traceTime = [5.0, 4.5, 4.0][max(0, min(2, config.level - 1))]
    }

    // MARK: Setup
    func start(tracker: MotionTracker) {
        root.addChild(sparkles.root)
        pickWords()
        // board in front, a little right, so the coach on the left stays in view
        var f = tracker.headForward; f.y = 0
        f = simd_length(f) > 0.01 ? simd_normalize(f) : [0, 0, -1]
        let right = simd_normalize(simd_cross(f, [0, 1, 0]))
        let head = tracker.head
        // high and a little further away: clear of the session panel (right) and the coach (left)
        boardPos = SIMD3<Float>(head.x, head.y + 0.32, head.z) + f * 1.9 + right * 0.08
        board.position = boardPos
        let away = SIMD3<Float>(boardPos.x - head.x, 0, boardPos.z - head.z)
        board.orientation = yawToward(simd_length(away) > 0.01 ? simd_normalize(away) : f)
        board.scale = [1.2, 1.2, 1.2]
        root.addChild(board)
        buildBoard()

        // the coach's badge: the letter being drawn, right beside the demonstration
        if let c = config.coachAnchor {
            let toBoard = SIMD3<Float>(boardPos.x - c.x, 0, boardPos.z - c.z)
            let side = simd_length(toBoard) > 0.01 ? simd_normalize(toBoard) : right
            badge.position = c - side * 0.6 + [0, 1.2, 0]           // on the coach's far side, clear of the board
            let away2 = SIMD3<Float>(badge.position.x - head.x, 0, badge.position.z - head.z)
            badge.orientation = yawToward(simd_length(away2) > 0.01 ? simd_normalize(away2) : f)
        } else {
            badge.position = boardPos - right * 0.75 + [0, 0.1, 0]
            badge.orientation = board.orientation
        }
        buildBadge()
        root.addChild(badge)

        startWord()
        feedback = "Trace each letter with your big toe. The letters spell a mystery word"
        SoundManager.shared.say("Trace each letter with your big toe. The letters spell a mystery word.")
    }

    private func pickWords() {
        let target = [14, 18, 22][max(0, min(2, config.level - 1))]
        var pool = Self.bank.filter { !Self.used.contains($0.text) }
        if pool.count < 4 { Self.used.removeAll(); pool = Self.bank }
        var total = 0
        var seen = Self.collected
        while total < target, !pool.isEmpty {
            // prefer words that bring new letters for the A–Z strip
            pool.shuffle()
            let best = pool.max { a, b in Set(a.text).subtracting(seen).count < Set(b.text).subtracting(seen).count }!
            words.append(best)
            Self.used.insert(best.text)
            seen.formUnion(best.text)
            total += best.text.count
            pool.removeAll { $0.text == best.text }
        }
    }

    private static func glass() -> UnlitMaterial { EnvironmentBuilder.glow(UIColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1), opacity: 0.62) }

    private func buildBoard() {
        let plate = ModelEntity(mesh: .generatePlane(width: 0.92, height: 0.95, cornerRadius: 0.07), materials: [Self.glass()])
        plate.position.z = -0.01
        board.addChild(plate)
        if let rim = EnvironmentBuilder.annulus(inner: 0.25, outer: 0.255) {
            ring.model = ModelComponent(mesh: rim, materials: [EnvironmentBuilder.glow(Palette.teal, opacity: 0.35)])
            ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            ring.position = [0, Self.letterY, -0.004]
            board.addChild(ring)
        }
        board.addChild(letterRoot)
        // tracer: a warm glowing dot with a halo
        tracer.addChild(ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [EnvironmentBuilder.glow(Palette.gold)]))
        tracer.addChild(ModelEntity(mesh: .generateSphere(radius: 0.042), materials: [EnvironmentBuilder.glow(Palette.gold, opacity: 0.25)]))
        tracer.isEnabled = false
        board.addChild(tracer)
        // A–Z collection strip
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for (i, ch) in letters.enumerated() {
            let t = LiveAnkle.text(String(ch), size: 0.024, color: Self.collected.contains(ch) ? Palette.gold : UIColor(white: 0.42, alpha: 1))
            let b = t.visualBounds(relativeTo: nil)
            t.position = [-0.39 + Float(i) * 0.0312 - b.center.x, -0.405 - b.min.y, 0.002]
            board.addChild(t)
            strip[ch] = t
        }
        let cap = LiveAnkle.text("YOUR ALPHABET", size: 0.014, color: UIColor(white: 0.6, alpha: 1))
        let cb = cap.visualBounds(relativeTo: nil)
        cap.position = [-cb.center.x, -0.345 - cb.min.y, 0.002]
        board.addChild(cap)
        optionRoot.position = [0.66, 0.05, 0]
        // "Done" for your turn: look at it and pinch (or simply raise a hand)
        let pill = ModelEntity(mesh: .generateBox(size: [0.3, 0.1, 0.02], cornerRadius: 0.045),
                               materials: [EnvironmentBuilder.glow(UIColor(red: 0.2, green: 0.62, blue: 0.6, alpha: 1))])
        doneButton.addChild(pill)
        let dl = LiveAnkle.text("✓ Done", size: 0.042, color: .white)
        let db = dl.visualBounds(relativeTo: nil)
        dl.position = [-db.center.x, -db.center.y, 0.012]
        doneButton.addChild(dl)
        let hint = LiveAnkle.text("or raise a hand", size: 0.02, color: UIColor(white: 0.8, alpha: 1))
        let hb = hint.visualBounds(relativeTo: nil)
        hint.position = [-hb.center.x, -0.085 - hb.center.y, 0.002]
        doneButton.addChild(hint)
        doneButton.position = [0.66, -0.22, 0]
        doneButton.components.set(CollisionComponent(shapes: [.generateBox(size: [0.3, 0.1, 0.04])]))
        doneButton.components.set(InputTargetComponent())
        doneButton.components.set(HoverEffectComponent())
        doneButton.isEnabled = false
        board.addChild(doneButton)
        board.addChild(optionRoot)
    }

    private func buildBadge() {
        let disc = ModelEntity(mesh: .generatePlane(width: 0.34, height: 0.4, cornerRadius: 0.06), materials: [Self.glass()])
        disc.position.z = -0.005
        badge.addChild(disc)
        let cap = LiveAnkle.text("NOW DRAWING", size: 0.022, color: Palette.teal)
        let cb = cap.visualBounds(relativeTo: nil)
        cap.position = [-cb.center.x, 0.135 - cb.min.y, 0.002]
        badge.addChild(cap)
        badge.addChild(badgeLetter)
    }

    // MARK: Words and letters
    private var word: Word { words[min(wordIndex, words.count - 1)] }

    private func startWord() {
        letterIndex = 0
        guessed = false
        guessOpen = false
        clearOptions()
        clue.removeFromParent()
        clue = Self.wrapped(word.clue, size: 0.03, width: 0.8, color: UIColor(white: 0.95, alpha: 1))
        let cb = clue.visualBounds(relativeTo: nil)
        clue.position = [-cb.center.x, 0.395 - cb.center.y, 0.002]
        board.addChild(clue)
        tiles.forEach { $0.removeFromParent() }
        tiles = []
        let n = word.text.count
        let w: Float = 0.085
        for i in 0..<n {
            let tile = Entity()
            let box = ModelEntity(mesh: .generateBox(size: [0.072, 0.082, 0.012], cornerRadius: 0.012),
                                  materials: [EnvironmentBuilder.glow(UIColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1))])
            tile.addChild(box)
            let q = LiveAnkle.text("?", size: 0.04, color: UIColor(white: 0.55, alpha: 1))
            let qb = q.visualBounds(relativeTo: nil)
            q.position = [-qb.center.x, -qb.center.y, 0.008]
            q.name = "glyph"
            tile.addChild(q)
            tile.position = [(Float(i) - Float(n - 1) / 2) * w, 0.29, 0]
            board.addChild(tile)
            tiles.append(tile)
        }
        phase = .intro
        timer = 0
        SoundManager.shared.say(word.clue)
    }

    private func startLetter() {
        let ch = Array(word.text)[letterIndex]
        buildLetter(ch)
        phase = .show
        timer = 0
        setBadge(ch)
        feedback = "Letter \(ch)"
        SoundManager.shared.say("Letter \(ch).")
        SoundManager.shared.play("sfx_tick", volume: 0.35)
        tipText = Self.tip(for: ch)
        // the guess opens part-way through the word
        if !guessed && !guessOpen && letterIndex == max(1, word.text.count - 2) { openGuess() }
    }

    private func setBadge(_ ch: Character) {
        badgeLetter.removeFromParent()
        let t = LiveAnkle.text(String(ch), size: 0.2, color: Palette.gold)
        let b = t.visualBounds(relativeTo: nil)
        t.position = [-b.center.x, -0.025 - b.center.y, 0.003]
        let h = Entity()
        h.addChild(t)
        let sub = LiveAnkle.text("Letter \(letterIndex + 1) of \(word.text.count)", size: 0.018, color: UIColor(white: 0.75, alpha: 1))
        let sb = sub.visualBounds(relativeTo: nil)
        sub.position = [-sb.center.x, -0.165 - sb.min.y, 0.003]
        h.addChild(sub)
        badge.addChild(h)
        badgeLetter = h
        badgePulse = 1
    }

    private func buildLetter(_ ch: Character) {
        Array(letterRoot.children).forEach { $0.removeFromParent() }
        segs = []; segAt = []
        path = Self.resample(Self.strokes(ch), step: 0.03)
        let dim = EnvironmentBuilder.glow(.white, opacity: 0.16)
        var strokeNo = 0
        for i in path.indices {
            if path[i].draw && (i == 0 || !path[i - 1].draw) {
                // numbered stroke start
                strokeNo += 1
                let p = map(path[i].p)
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.013), materials: [EnvironmentBuilder.glow(Palette.mint)])
                dot.position = p + [0, 0, 0.004]
                letterRoot.addChild(dot)
                let num = LiveAnkle.text("\(strokeNo)", size: 0.022, color: Palette.mint)
                let nb = num.visualBounds(relativeTo: nil)
                num.position = p + [-0.03 - nb.extents.x / 2, 0.01, 0.004]
                letterRoot.addChild(num)
            }
            guard i > 0, path[i].draw, path[i - 1].draw else { continue }
            let a = map(path[i - 1].p), b = map(path[i].p)
            let d = b - a
            let len = simd_length(d)
            guard len > 0.0005 else { continue }
            let s = ModelEntity(mesh: .generateBox(size: [len + 0.012, 0.014, 0.004], cornerRadius: 0.002), materials: [dim])
            s.position = (a + b) / 2
            s.orientation = simd_quatf(angle: atan2(d.y, d.x), axis: [0, 0, 1])
            letterRoot.addChild(s)
            segs.append(s)
            segAt.append(i)
        }
        lit = 0
        tracer.position = map(path.first?.p ?? [0.5, 0.5]) + [0, 0, 0.01]
        tracer.isEnabled = true
    }

    private var lit = 0

    private func map(_ p: SIMD2<Float>) -> SIMD3<Float> {
        [(p.x - 0.5) * Self.letterH * 0.85, (p.y - 0.5) * Self.letterH + Self.letterY, 0]
    }

    // MARK: Guess
    private func openGuess() {
        guessOpen = true
        clearOptions()
        let title = LiveAnkle.text("Guess the word?", size: 0.026, color: Palette.gold)
        let tb = title.visualBounds(relativeTo: nil)
        title.position = [-tb.center.x, 0.16, 0]
        optionRoot.addChild(title)
        var choices = [word.text] + word.decoys.prefix(2)
        choices.shuffle()
        for (i, w) in choices.enumerated() {
            let o = Entity()
            let pill = ModelEntity(mesh: .generateBox(size: [0.26, 0.085, 0.02], cornerRadius: 0.035),
                                   materials: [EnvironmentBuilder.glow(UIColor(red: 0.16, green: 0.36, blue: 0.42, alpha: 1), opacity: 0.92)])
            o.addChild(pill)
            let t = LiveAnkle.text(w, size: 0.036, color: .white)
            let b = t.visualBounds(relativeTo: nil)
            t.position = [-b.center.x, -b.center.y, 0.012]
            o.addChild(t)
            o.position = [0, 0.07 - Float(i) * 0.11, 0]
            o.components.set(CollisionComponent(shapes: [.generateBox(size: [0.26, 0.085, 0.04])]))
            o.components.set(InputTargetComponent())
            o.components.set(HoverEffectComponent())
            optionRoot.addChild(o)
            options.append((o, w))
        }
        feedback = "Guess the word! Tap your answer"
        SoundManager.shared.say("Guess the word! Tap your answer.")
        SoundManager.shared.play("sfx_shimmer", volume: 0.4)
    }

    private func clearOptions() {
        Array(optionRoot.children).forEach { $0.removeFromParent() }
        options = []
    }

    func handleTap(_ entity: Entity) -> Bool {
        if phase == .yourTurn {
            var e: Entity? = entity
            while let c = e { if c === doneButton { confirmLetter(by: "tap"); return true }; e = c.parent }
        }
        guard guessOpen else { return false }
        var cur: Entity? = entity
        while let c = cur {
            if let o = options.first(where: { $0.e === c }) {
                if o.word == word.text {
                    guessed = true
                    guessOpen = false
                    score += 3
                    clearOptions()
                    feedback = "Yes! You guessed it. Keep tracing to write it out"
                    SoundManager.shared.say("Yes! You guessed it.", interrupt: true)
                    SoundManager.shared.play("sfx_levelup", volume: 0.5)
                    sparkles.burst(at: board.position(relativeTo: nil) + [0, 0.3, 0.05], color: Palette.gold, count: 22, speed: 0.6, size: 0.012)
                } else {
                    o.e.isEnabled = false
                    feedback = "Good try. Keep tracing to find out"
                    SoundManager.shared.say("Good try. Keep tracing to find out.", interrupt: true)
                }
                return true
            }
            cur = c.parent
        }
        return false
    }

    // MARK: Update
    func update(dt: Float, time: Double, tracker: MotionTracker) {
        guard !finished else { return }
        timer += dt
        sparkles.update(dt: dt)
        // emphasis on the coach's badge: a soft pulse on every new letter
        badgePulse = max(0, badgePulse - dt * 1.4)
        let k = 1 + 0.14 * badgePulse
        badgeLetter.scale = [k, k, k]
        ring.scale = [1 + 0.05 * sin(Float(time) * 2.2), 1, 1 + 0.05 * sin(Float(time) * 2.2)]

        switch phase {
        case .intro:
            if timer > 4.0 { startLetter() }
        case .show:
            if timer > 0.8 { phase = .trace; timer = 0 }
        case .trace:
            let u = min(1, timer / traceTime)
            let idx = Int(u * Float(max(1, path.count - 1)))
            if path.indices.contains(idx) {
                tracer.position = map(path[idx].p) + [0, 0, 0.012]
                tracer.components.set(OpacityComponent(opacity: path[idx].draw ? 1 : 0.45))
            }
            let bright = EnvironmentBuilder.glow(Palette.gold)
            while lit < segs.count && segAt[lit] <= idx {
                segs[lit].model?.materials = [bright]
                lit += 1
            }
            if u >= 1 { startTurn() }
        case .yourTurn:
            // the guide keeps looping slowly while you draw it yourself
            let loop = (timer / (traceTime * 1.4)).truncatingRemainder(dividingBy: 1)
            let idx = Int(loop * Float(max(1, path.count - 1)))
            if path.indices.contains(idx) {
                tracer.position = map(path[idx].p) + [0, 0, 0.012]
                tracer.components.set(OpacityComponent(opacity: path[idx].draw ? 0.7 : 0.3))
            }
            let pulse = 1 + 0.06 * sin(timer * 4)
            doneButton.scale = [pulse, pulse, pulse]
            // a hand raised above the shoulders (held briefly) = "done"
            let hy = max(tracker.leftHand?.y ?? -9, tracker.rightHand?.y ?? -9)
            if tracker.running && hy > tracker.head.y - 0.12 { raisedFor += dt } else { raisedFor = 0 }
            if raisedFor > 0.35 && timer > 1 { confirmLetter(by: "hand"); break }
            if timer > 12 && !reminded {
                reminded = true
                feedback = "When you've drawn it with your toe, tap Done or raise a hand"
                SoundManager.shared.say("When you've drawn it with your toe, tap done or raise a hand.")
            }
            if timer > 40 { confirmLetter(by: "time") }        // never stuck
        case .reveal:
            if timer > 0.7 {
                letterIndex += 1
                if letterIndex >= word.text.count { finishWord() } else { startLetter() }
            }
        case .celebrate:
            if timer > 4.2 {
                wordIndex += 1
                if wordIndex >= words.count {
                    phase = .done
                    finished = true
                    feedback = "Round complete. Wonderful writing"
                    SoundManager.shared.say("Round complete. Wonderful writing.")
                } else { startWord() }
            }
        case .done:
            break
        }
    }

    private func startTurn() {
        let ch = Array(word.text)[letterIndex]
        phase = .yourTurn
        timer = 0
        raisedFor = 0
        reminded = false
        doneButton.isEnabled = true
        let soft = EnvironmentBuilder.glow(Palette.gold, opacity: 0.55)
        segs.forEach { $0.model?.materials = [soft] }
        feedback = "Your turn: follow the trainer and draw the \(ch) with your big toe"
        SoundManager.shared.say(lettersDone < 2 ? "Your turn. Draw it with your big toe, then tap done or raise a hand." : "Your turn.")
    }

    private func confirmLetter(by how: String) {
        guard phase == .yourTurn else { return }
        doneButton.isEnabled = false
        revealLetter()
    }

    private func revealLetter() {
        let ch = Array(word.text)[letterIndex]
        phase = .reveal
        timer = 0
        lettersDone += 1
        score += 1
        tracer.isEnabled = false
        let done = EnvironmentBuilder.glow(Palette.teal)
        segs.forEach { $0.model?.materials = [done] }
        // flip the tile
        let tile = tiles[letterIndex]
        tile.findEntity(named: "glyph")?.removeFromParent()
        if let box = tile.children.first as? ModelEntity { box.model?.materials = [EnvironmentBuilder.glow(UIColor(red: 0.95, green: 0.78, blue: 0.36, alpha: 1))] }
        let t = LiveAnkle.text(String(ch), size: 0.046, color: UIColor(red: 0.1, green: 0.1, blue: 0.16, alpha: 1))
        let b = t.visualBounds(relativeTo: nil)
        t.position = [-b.center.x, -b.center.y, 0.008]
        tile.addChild(t)
        sparkles.burst(at: tile.position(relativeTo: nil) + [0, 0, 0.03], color: Palette.teal, count: 8, speed: 0.4, size: 0.008)
        // collect it on the A–Z strip
        if !Self.collected.contains(ch) {
            Self.collected.insert(ch)
            strip[ch]?.model?.materials = [UnlitMaterial(color: Palette.gold)]
        }
        SoundManager.shared.play("sfx_chime", volume: 0.4)
        praiseCount += 1
        let line = Self.praise[(praiseCount + wordIndex) % Self.praise.count]
        feedback = String(line.dropLast())
        if praiseCount % 3 == 0 { SoundManager.shared.say(line) }
    }

    private func finishWord() {
        phase = .celebrate
        timer = 0
        clearOptions()
        guessOpen = false
        Array(letterRoot.children).forEach { $0.removeFromParent() }
        // the word glows big in the letter space
        let big = LiveAnkle.text(word.text, size: 0.13, color: Palette.gold)
        let b = big.visualBounds(relativeTo: nil)
        big.position = [-b.center.x, Self.letterY + 0.03 - b.center.y, 0.01]
        letterRoot.addChild(big)
        let cheer = Self.wrapped(word.cheer, size: 0.03, width: 0.8, color: .white)
        let cb = cheer.visualBounds(relativeTo: nil)
        cheer.position = [-cb.center.x, Self.letterY - 0.12 - cb.center.y, 0.01]
        letterRoot.addChild(cheer)
        let colours = [Palette.gold, Palette.teal, Palette.pink, Palette.mint, Palette.violet]
        for (i, c) in colours.enumerated() {
            sparkles.burst(at: board.position(relativeTo: nil) + [Float(i - 2) * 0.15, 0.05, 0.05], color: c, count: 12, speed: 0.6, size: 0.01)
        }
        score += 2
        feedback = "You spelled \(word.text)! \(word.cheer)"
        SoundManager.shared.play("sfx_levelup", volume: 0.55)
        SoundManager.shared.say("You spelled \(word.text.lowercased())! \(word.cheer)")
        setBadgeWord()
    }

    private func setBadgeWord() {
        badgeLetter.removeFromParent()
        let t = LiveAnkle.text(word.text, size: word.text.count > 5 ? 0.06 : 0.075, color: Palette.gold)
        let b = t.visualBounds(relativeTo: nil)
        t.position = [-b.center.x, -0.02 - b.center.y, 0.003]
        let h = Entity(); h.addChild(t)
        badge.addChild(h)
        badgeLetter = h
        badgePulse = 1
    }

    func stop() {
        finished = true
        sparkles.clear()
        root.removeFromParent()
    }

    // MARK: Learning: what each kind of stroke trains
    private static func tip(for ch: Character) -> String {
        if "COSUGQJ".contains(ch) { return "Curves take the ankle through every direction, so all the muscles around it share the work." }
        if "AVWXKMNYZ".contains(ch) { return "Diagonals combine pointing and turning the foot: the outer ankle muscles that guard against another sprain." }
        if "EFHLT".contains(ch) { return "Straight lines: up and down trains your shin and calf, side to side turns the sole in and out." }
        return "Move from the ankle, not the knee. Big, slow letters, only as far as is comfortable."
    }

    // MARK: Text helper
    private static func wrapped(_ s: String, size: CGFloat, width: CGFloat, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(s, extrusionDepth: 0.001, font: .systemFont(ofSize: size, weight: .semibold),
                                             containerFrame: CGRect(x: 0, y: 0, width: width, height: 0.3),
                                             alignment: .center, lineBreakMode: .byWordWrapping)
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
    }

    // MARK: Letter strokes (unit box, x right, y up), in the usual stroke order
    private static func p(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2<Float>(x, y) }
    private static func arc(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ a0: Float, _ a1: Float, _ n: Int = 20) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for i in 0...n {
            let a = (a0 + (a1 - a0) * Float(i) / Float(n)) * .pi / 180
            out.append(SIMD2<Float>(cx + rx * cos(a), cy + ry * sin(a)))
        }
        return out
    }

    static func strokes(_ c: Character) -> [[SIMD2<Float>]] {
        switch c {
        case "A": return [[p(0, 0), p(0.5, 1), p(1, 0)], [p(0.22, 0.42), p(0.78, 0.42)]]
        case "B":
            let top: [SIMD2<Float>] = [p(0, 1), p(0.5, 1)] + arc(0.5, 0.75, 0.3, 0.25, 90, -90) + [p(0, 0.5)]
            let bottom: [SIMD2<Float>] = [p(0, 0.5), p(0.55, 0.5)] + arc(0.55, 0.25, 0.33, 0.25, 90, -90) + [p(0, 0)]
            return [[p(0, 1), p(0, 0)], top, bottom]
        case "C": return [arc(0.55, 0.5, 0.45, 0.5, 50, 310)]
        case "D":
            let bowl: [SIMD2<Float>] = [p(0, 1), p(0.35, 1)] + arc(0.35, 0.5, 0.6, 0.5, 90, -90) + [p(0, 0)]
            return [[p(0, 1), p(0, 0)], bowl]
        case "E": return [[p(0.95, 1), p(0, 1), p(0, 0), p(0.95, 0)], [p(0, 0.5), p(0.75, 0.5)]]
        case "F": return [[p(0.95, 1), p(0, 1), p(0, 0)], [p(0, 0.5), p(0.75, 0.5)]]
        case "G": return [arc(0.55, 0.5, 0.45, 0.5, 50, 340) + [p(0.97, 0.45), p(0.6, 0.45)]]
        case "H": return [[p(0, 1), p(0, 0)], [p(1, 1), p(1, 0)], [p(0, 0.5), p(1, 0.5)]]
        case "I": return [[p(0.5, 1), p(0.5, 0)], [p(0.2, 1), p(0.8, 1)], [p(0.2, 0), p(0.8, 0)]]
        case "J": return [[p(0.75, 1), p(0.75, 0.3)] + arc(0.45, 0.3, 0.3, 0.3, 0, -180)]
        case "K": return [[p(0, 1), p(0, 0)], [p(0.95, 1), p(0, 0.42)], [p(0.3, 0.6), p(1, 0)]]
        case "L": return [[p(0, 1), p(0, 0), p(0.9, 0)]]
        case "M": return [[p(0, 0), p(0, 1), p(0.5, 0.4), p(1, 1), p(1, 0)]]
        case "N": return [[p(0, 0), p(0, 1), p(1, 0), p(1, 1)]]
        case "O": return [arc(0.5, 0.5, 0.45, 0.5, 90, 450, 32)]
        case "P": return [[p(0, 1), p(0, 0)], [p(0, 1), p(0.5, 1)] + arc(0.5, 0.75, 0.32, 0.25, 90, -90) + [p(0, 0.5)]]
        case "Q": return [arc(0.5, 0.5, 0.45, 0.5, 90, 450, 32), [p(0.6, 0.25), p(1, -0.05)]]
        case "R": return [[p(0, 1), p(0, 0)], [p(0, 1), p(0.5, 1)] + arc(0.5, 0.75, 0.32, 0.25, 90, -90) + [p(0, 0.5)], [p(0.4, 0.5), p(1, 0)]]
        case "S": return [arc(0.5, 0.75, 0.4, 0.25, 30, 270) + arc(0.5, 0.25, 0.4, 0.25, 90, -150)]
        case "T": return [[p(0, 1), p(1, 1)], [p(0.5, 1), p(0.5, 0)]]
        case "U": return [[p(0, 1), p(0, 0.4)] + arc(0.5, 0.4, 0.5, 0.4, 180, 360) + [p(1, 1)]]
        case "V": return [[p(0, 1), p(0.5, 0), p(1, 1)]]
        case "W": return [[p(0, 1), p(0.25, 0), p(0.5, 0.6), p(0.75, 0), p(1, 1)]]
        case "X": return [[p(0, 1), p(1, 0)], [p(1, 1), p(0, 0)]]
        case "Y": return [[p(0, 1), p(0.5, 0.5), p(1, 1)], [p(0.5, 0.5), p(0.5, 0)]]
        case "Z": return [[p(0, 1), p(1, 1), p(0, 0), p(1, 0)]]
        default: return [arc(0.5, 0.5, 0.45, 0.5, 90, 450, 32)]
        }
    }

    /// Evenly spaced points along the strokes; pen-up moves between strokes are included (draw = false) so the
    /// tracer glides to the next starting point instead of jumping.
    static func resample(_ strokes: [[SIMD2<Float>]], step: Float) -> [(p: SIMD2<Float>, draw: Bool)] {
        var out: [(p: SIMD2<Float>, draw: Bool)] = []
        func walk(_ pts: [SIMD2<Float>], draw: Bool) {
            guard let first = pts.first, pts.count > 1 else { return }
            out.append((first, draw))
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let n = max(1, Int((simd_length(b - a) / step).rounded(.up)))
                for k in 1...n { out.append((a + (b - a) * Float(k) / Float(n), draw)) }
            }
        }
        for (i, s) in strokes.enumerated() {
            if i > 0, let last = out.last?.p, let next = s.first {
                walk([last, next], draw: false)          // pen up
            }
            walk(s, draw: true)
        }
        return out
    }
}
