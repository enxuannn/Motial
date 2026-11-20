import Foundation

enum GameKind: String, Codable {
    case balanceBloom, ballCatch, riverStones, rhythmSteps, lanternGlide, dawnDrive, cockpitDrive, wordGarden
}

enum MeasureMode: String, Codable {
    case none          // guided by timer / voice only
    case sway          // head-sway steadiness during a hold
    case headReps      // repetitions counted from head height (heel raises, squats)
    case hops          // hop landings
}

enum ExerciseKind: Equatable {
    case reps
    case hold
    case game(GameKind)
}

struct Dosage: Equatable {
    var sets: Int
    var reps: Int? = nil
    var holdSeconds: Int? = nil
    var restSeconds: Int = 20

    var text: String {
        if let r = reps, r > 1 { return "\(sets) × \(r)" }
        if let h = holdSeconds { return "\(sets) × \(h) s" }
        return "\(sets) rounds"
    }
}

struct Exercise: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let stages: ClosedRange<Int>          // RehabStage raw values where it is appropriate
    let seated: Bool
    let clip: String                      // coach animation clip (without side suffix)
    let kind: ExerciseKind
    let measure: MeasureMode
    let base: Dosage
    let steps: [String]
    let cues: [String]                    // spoken during the set
    let purpose: String
    let evidence: [String]                // Evidence ids
    let cautions: [String]
    var requiresHopClearance = false
    var singleLeg = false

    func fits(_ stage: RehabStage) -> Bool { stages.contains(stage.rawValue) }

    /// Dose adapted to level 1 – 3.
    func dosage(level: Int) -> Dosage {
        var d = base
        let l = max(1, min(3, level))
        if let r = base.reps { d.reps = r + (l - 1) * (r >= 10 ? 3 : 2) }
        if let h = base.holdSeconds { d.holdSeconds = h + (l - 1) * 10 }
        if l == 3 { d.sets = base.sets + (base.sets < 3 ? 1 : 0) }
        return d
    }
}

enum ExerciseLibrary {
    static let all: [Exercise] = [
        Exercise(id: "ankle_pumps", title: "Ankle Pumps", symbol: "arrow.up.and.down", stages: 1...2, seated: true,
                 clip: "ankle_pumps", kind: .reps, measure: .none, base: Dosage(sets: 2, reps: 15, restSeconds: 15),
                 steps: ["Sit tall with the injured leg out in front, heel resting or just off the floor.",
                         "Pull your toes up towards you, then point them away.",
                         "Move slowly and stay within a comfortable range."],
                 cues: ["Toes up", "and point", "Nice and slow", "Stay comfortable"],
                 purpose: "Keeps the joint moving and pumps swelling away. Early protected movement is part of every guideline-based programme.",
                 evidence: ["jospt2021", "peacelove", "vuurberg2018"], cautions: ["Stop if pain goes above 3/10."]),
        Exercise(id: "ankle_alphabet", title: "Ankle Alphabet", symbol: "character.cursor.ibeam", stages: 1...2, seated: true,
                 clip: "ankle_alphabet", kind: .game(.wordGarden), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 15),
                 steps: ["Sit with the leg supported and the foot free.",
                         "Follow the trainer: draw each letter in the air with your big toe, following the numbered strokes.",
                         "When you've drawn it, raise a hand or tap Done.",
                         "The letters spell a mystery word: read the clue and tap your guess.",
                         "Move from the ankle, not the knee. Collect the whole alphabet A to Z."],
                 cues: ["Big, smooth letters", "Move from the ankle", "Keep breathing"],
                 purpose: "Restores movement in every direction with no load on the healing ligament.",
                 evidence: ["jospt2021"], cautions: ["Small letters are fine early on."]),
        Exercise(id: "seated_eversion", title: "Outer Ankle Press", symbol: "arrow.left.and.right", stages: 1...3, seated: true,
                 clip: "seated_eversion", kind: .reps, measure: .none, base: Dosage(sets: 3, reps: 10, restSeconds: 30),
                 steps: ["Loop a resistance band around the forefoot (or press the outer foot against a chair leg).",
                         "Turn the sole slowly outwards against the resistance.", "Hold for 2 seconds and return slowly."],
                 cues: ["Turn the foot out", "Hold", "And slowly back"],
                 purpose: "Strengthens the peroneal (fibularis) muscles that protect the outside of the ankle.",
                 evidence: ["jospt2021", "doherty2017"], cautions: ["No band? Press against a fixed object instead."]),
        Exercise(id: "seated_inversion", title: "Inner Ankle Press", symbol: "arrow.right.and.line.vertical.and.arrow.left", stages: 1...3, seated: true,
                 clip: "seated_inversion", kind: .reps, measure: .none, base: Dosage(sets: 3, reps: 10, restSeconds: 30),
                 steps: ["Loop a resistance band around the forefoot, anchored to the outside (or press the inner foot against a chair leg).",
                         "Turn the sole slowly inwards against the resistance.", "Hold for 2 seconds and return slowly."],
                 cues: ["Turn the foot in", "Hold", "And slowly back"],
                 purpose: "Strengthens tibialis posterior, which supports the arch and the inner ankle, without stretching the healing inner ligament.",
                 evidence: ["deltoidNCH", "jospt2021"], cautions: ["Stay within a comfortable range.", "No band? Press against a fixed object instead."]),
        Exercise(id: "calf_raise", title: "Double Heel Raises", symbol: "arrow.up.to.line", stages: 2...3, seated: false,
                 clip: "calf_raise", kind: .reps, measure: .headReps, base: Dosage(sets: 3, reps: 10, restSeconds: 40),
                 steps: ["Stand facing a wall or the back of a sturdy chair, fingertips resting on it.",
                         "Rise onto the balls of both feet.", "Lower slowly over three seconds."],
                 cues: ["Rise up", "and lower slowly", "Weight through both feet"],
                 purpose: "Rebuilds calf strength for normal walking and stairs.",
                 evidence: ["jospt2021"], cautions: ["Keep your hands on the support."]),
        Exercise(id: "dawn_drive", title: "Dawn Drive", symbol: "car.fill", stages: 2...3, seated: false,
                 clip: "calf_raise", kind: .game(.dawnDrive), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 40),
                 steps: ["Stand facing a wall or the back of a sturdy chair, fingertips resting on it.",
                         "Your ankle is the accelerator: rise slowly onto your toes to drive, lower your heels slowly to ease off.",
                         "Ease off before the gold corners for a clean corner, collect orbs on the straights, and race your own ghost."],
                 cues: ["Rise slowly onto your toes", "Ease off before the corner", "Lower over three seconds", "Fingertips on your support"],
                 purpose: "Slow heel raises with controlled lowering build calf strength and control; the corners train you to release slowly.",
                 evidence: ["jospt2021", "gamesNote"], cautions: ["Keep your hands on the support.", "It's a race against your own control, not the clock."]),
        Exercise(id: "dawn_drive_cockpit", title: "Dawn Drive: Cockpit", symbol: "steeringwheel", stages: 1...4, seated: true,
                 clip: "ankle_pumps", kind: .game(.cockpitDrive), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 45),
                 steps: ["Sit on a sturdy chair with your back supported. Strap your iPhone to the top of your foot and open Motial Pedal.",
                         "Your foot is the accelerator: point your toes down slowly to drive, bring them up slowly to ease off before each gold lantern gate.",
                         "Hold your hands up as if on a wheel and tilt it to change lanes for the light orbs. Rest your arms any time: lane assist steers."],
                 cues: ["Toes down slowly", "Ease off before the gate", "Look ahead to the horizon", "Breathe"],
                 purpose: "Controlled ankle pumping with a seated drive: smooth pressing and slow release train ankle control while you sit.",
                 evidence: ["jospt2021", "gamesNote", "lin2021"],
                 cautions: ["Seated only, back supported.", "If you feel dizzy or queasy, tap STOP and look at your real room.", "Move only within a comfortable range."]),
        Exercise(id: "dawn_drive_seated", title: "Dawn Drive (seated)", symbol: "car", stages: 1...2, seated: true,
                 clip: "ankle_pumps", kind: .game(.dawnDrive), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 30),
                 steps: ["Sit on a sturdy chair. Strap your iPhone to the top of your foot with a sports armband.",
                         "Open Motial Pedal on the iPhone and set your resting position and comfortable range.",
                         "Point your toes down slowly to drive, bring them back up slowly to ease off before the gold corners."],
                 cues: ["Toes down slowly", "Ease off before the corner", "Smooth pedal, more grip", "Breathe"],
                 purpose: "Controlled ankle pumping with a playful goal: keeps the ankle moving and trains smooth control.",
                 evidence: ["jospt2021", "gamesNote"], cautions: ["Stay seated the whole time.", "Move only within a comfortable range."]),
        Exercise(id: "lantern_glide_seated", title: "Lantern Glide (seated)", symbol: "sailboat", stages: 1...2, seated: true,
                 clip: "ankle_pumps", kind: .game(.lanternGlide), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 30),
                 steps: ["Sit on a sturdy chair. Strap your iPhone to the top of your foot with a sports armband.",
                         "Open Motial Pedal on the iPhone and set your resting position and comfortable range.",
                         "Point your toes down slowly to glide, then bring them back up. A smooth, steady pace lights the lanterns."],
                 cues: ["Toes down slowly", "And back up", "Smooth and steady lights the lanterns", "Breathe"],
                 purpose: "Gentle, controlled ankle pumping keeps the ankle moving and helps swelling settle, with a calm goal to follow.",
                 evidence: ["jospt2021", "gamesNote"], cautions: ["Stay seated the whole time.", "Move only within a comfortable range."]),
        Exercise(id: "lantern_glide", title: "Lantern Glide", symbol: "sailboat.fill", stages: 2...3, seated: false,
                 clip: "calf_raise", kind: .game(.lanternGlide), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 40),
                 steps: ["Stand facing a wall or the back of a sturdy chair, fingertips resting on it.",
                         "Rise slowly onto your toes: your little boat glides forward across the lake.",
                         "Lower your heels over three seconds. A smooth, steady pace lights the lanterns; jerky movement only makes ripples."],
                 cues: ["Rise slowly onto your toes", "Lower over three seconds", "Smooth and steady lights the lanterns", "Fingertips on your support"],
                 purpose: "Slow, controlled heel raises rebuild calf strength and control, with a calm goal to follow instead of counting.",
                 evidence: ["jospt2021", "gamesNote"], cautions: ["Keep your hands on the support.", "There is no race: slower is better."]),
        Exercise(id: "knee_to_wall", title: "Knee-to-Wall Lunge", symbol: "figure.cooldown", stages: 2...3, seated: false,
                 clip: "knee_to_wall", kind: .reps, measure: .none, base: Dosage(sets: 3, reps: 10, restSeconds: 30),
                 steps: ["Stand facing a wall, injured foot in front, heel down.", "Bend the front knee towards the wall without lifting the heel.",
                         "Move back and repeat."],
                 cues: ["Knee forward", "Heel stays down", "And back"],
                 purpose: "Restores weight-bearing dorsiflexion, measured clinically with the weight-bearing lunge test.",
                 evidence: ["jospt2021"], cautions: ["A stretch is normal; sharp pain is not."]),
        Exercise(id: "supported_sls", title: "Supported One-Leg Stand", symbol: "hand.raised", stages: 2...2, seated: false,
                 clip: "single_leg_stance", kind: .hold, measure: .sway, base: Dosage(sets: 3, holdSeconds: 15, restSeconds: 30),
                 steps: ["Stand next to a wall or kitchen bench with fingertips resting on it.", "Lift the other foot just off the floor.",
                         "Keep the standing knee soft and look ahead."],
                 cues: ["Fingertips light", "Soft knee", "Look ahead", "Breathe"],
                 purpose: "The first step of balance (proprioceptive) training — the intervention with the strongest evidence for preventing re-sprains.",
                 evidence: ["jospt2021", "hupperets2009"], cautions: ["Keep the support within reach at all times."], singleLeg: true),
        Exercise(id: "single_leg_stance", title: "Balance Bloom", symbol: "camera.macro", stages: 3...4, seated: false,
                 clip: "single_leg_stance", kind: .game(.balanceBloom), measure: .sway, base: Dosage(sets: 3, holdSeconds: 20, restSeconds: 30),
                 steps: ["Stand on the injured leg near a wall or chair.", "Lift the other foot and hold still.",
                         "The steadier you are, the more the lotus blooms."],
                 cues: ["Stay tall", "Soft knee", "Let the lotus bloom", "Breathe slowly"],
                 purpose: "Single-leg balance training reduces the risk of another sprain by about a third.",
                 evidence: ["hupperets2009", "jospt2021", "doherty2017"], cautions: ["Put your foot down whenever you need to — that's part of training."], singleLeg: true),
        Exercise(id: "sls_head_turns", title: "One-Leg Stand + Head Turns", symbol: "arrow.left.arrow.right.circle", stages: 3...4, seated: false,
                 clip: "sls_head_turns", kind: .hold, measure: .sway, base: Dosage(sets: 2, holdSeconds: 20, restSeconds: 30),
                 steps: ["Balance on the injured leg.", "Slowly turn your head left and right while keeping balance."],
                 cues: ["Turn slowly", "Keep the hips still", "Back to centre"],
                 purpose: "Challenges the balance system the way daily life and sport do.",
                 evidence: ["jospt2021"], cautions: ["Not if you feel dizzy."], singleLeg: true),
        Exercise(id: "sls_reach_catch", title: "One-Leg Catch", symbol: "baseball", stages: 3...4, seated: false,
                 clip: "sls_reach_catch", kind: .game(.ballCatch), measure: .sway, base: Dosage(sets: 2, reps: 8, restSeconds: 40),
                 steps: ["Warm up with a few catches on both feet.", "Then balance on the injured leg and catch with your glove hand.",
                         "Throws come from new directions as you level up: reach, catch, back to the middle."],
                 cues: ["Eyes on the ball", "Reach and catch", "Back to centre"],
                 purpose: "Catching while balancing on one leg (dual-task balance) is a phase III step in clinical ankle sprain protocols. Throws from changing directions train reactive balance.",
                 evidence: ["mgh", "jospt2021"], cautions: ["Only reach as far as you can stay balanced. Put the foot down whenever you need to."], singleLeg: true),
        Exercise(id: "sl_mini_squat", title: "One-Leg Mini Squat", symbol: "figure.strengthtraining.traditional", stages: 3...4, seated: false,
                 clip: "sl_mini_squat", kind: .reps, measure: .headReps, base: Dosage(sets: 3, reps: 6, restSeconds: 40),
                 steps: ["Stand on the injured leg, fingertips on a support if needed.", "Bend the knee a little, keeping it over your toes.",
                         "Stand tall again."],
                 cues: ["Bend a little", "Knee over toes", "And stand tall"],
                 purpose: "Builds control of the whole leg, which also protects the ankle.",
                 evidence: ["jospt2021"], cautions: ["Small range is enough."], singleLeg: true),
        Exercise(id: "sl_calf_raise", title: "One-Leg Heel Raise", symbol: "arrow.up.circle", stages: 3...4, seated: false,
                 clip: "sl_calf_raise", kind: .reps, measure: .headReps, base: Dosage(sets: 3, reps: 8, restSeconds: 45),
                 steps: ["Hold a wall or chair lightly.", "Rise onto the ball of the injured foot only.", "Lower slowly."],
                 cues: ["Up tall", "Slowly down", "Keep the ankle straight"],
                 purpose: "Single-leg heel raise endurance is a common return-to-sport benchmark.",
                 evidence: ["jospt2021"], cautions: ["Use your hands for support."], singleLeg: true),
        Exercise(id: "stepping_stones", title: "Stepping Stones", symbol: "circle.grid.3x3", stages: 2...4, seated: false,
                 clip: "step_beat", kind: .game(.riverStones), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 30),
                 steps: ["Stones appear on your floor across a river.", "Step from stone to stone at your own pace, and settle on each one.",
                         "Unlock levels: straight path, zig-zag, then side-step crossing."],
                 cues: ["Step and settle", "Nice control", "Next stone"],
                 purpose: "Walking practice with controlled weight transfer, turned into a calm challenge.",
                 evidence: ["jospt2021", "mgh", "gamesNote", "lin2021"], cautions: ["Clear 3 metres of floor in front of you."]),
        Exercise(id: "rhythm_steps", title: "Rhythm Steps", symbol: "music.note", stages: 2...4, seated: false,
                 clip: "step_beat", kind: .game(.rhythmSteps), measure: .none, base: Dosage(sets: 2, reps: 1, restSeconds: 40),
                 steps: ["Stand in the centre ring. Choose a song you love.", "Step onto the glowing pad on the beat, then back to the centre. Early on, keep your feet planted and just lean toward the pad while holding a support.",
                         "Every hit makes your world react: ripples, droplets, flowers or shooting stars."],
                 cues: ["On the beat", "Back to centre", "You've got this"],
                 purpose: "Quick, controlled steps in different directions (agility) with music to keep it fun.",
                 evidence: ["jospt2021", "mgh", "gamesNote", "lin2021"], cautions: ["No backward steps. Stop if the ankle feels unstable."]),
        Exercise(id: "hop_forward", title: "Forward Hop & Stick", symbol: "figure.jumprope", stages: 4...4, seated: false,
                 clip: "hop_forward", kind: .reps, measure: .hops, base: Dosage(sets: 3, reps: 5, restSeconds: 60),
                 steps: ["Stand on the injured leg.", "Hop a short distance forward and land softly.", "Hold the landing for 2 seconds."],
                 cues: ["Small hop", "Soft landing", "Stick it"],
                 purpose: "Hop tests and landing control are used to judge readiness for sport.",
                 evidence: ["jospt2021", "mgh", "paass2021"], cautions: ["Only after clinician clearance."], requiresHopClearance: true, singleLeg: true),
        Exercise(id: "side_hop", title: "Side Hops", symbol: "arrow.left.and.right.square", stages: 4...4, seated: false,
                 clip: "side_hop", kind: .reps, measure: .hops, base: Dosage(sets: 3, reps: 5, restSeconds: 60),
                 steps: ["Stand on the injured leg.", "Hop sideways a short distance and land softly.", "Hold, then hop back."],
                 cues: ["Hop across", "Land soft", "Hold"],
                 purpose: "Side-to-side control is where re-sprains usually happen.",
                 evidence: ["jospt2021"], cautions: ["Only after clinician clearance."], requiresHopClearance: true, singleLeg: true),
        Exercise(id: "river_hops", title: "River Hops", symbol: "drop", stages: 4...4, seated: false,
                 clip: "hop_forward", kind: .game(.riverStones), measure: .hops, base: Dosage(sets: 2, reps: 1, restSeconds: 60),
                 steps: ["First crossing: small two-foot hops to warm up.", "Then hop on the injured leg from stone to stone and stick each landing.",
                         "Unlock levels: forward hops, zig-zag hops, then quarter-turn hops."],
                 cues: ["Small hop", "Stick the landing", "Great control"],
                 purpose: "Progressive hopping with landing control, the final step before sport.",
                 evidence: ["jospt2021", "mgh", "paass2021"], cautions: ["Clear 3 metres of floor. Only after clinician clearance."],
                 requiresHopClearance: true, singleLeg: true),
    ]

    static func byID(_ id: String) -> Exercise? { all.first { $0.id == id } }
}

// MARK: - Evidence

struct Evidence: Identifiable {
    let id: String
    let citation: String
    let finding: String
    let url: String
    /// "McKay et al. 2001": first author and year, from the citation.
    var shortCite: String {
        let author = citation.split(separator: " ").first.map(String.init)?.trimmingCharacters(in: .punctuationCharacters) ?? citation
        let year = citation.range(of: #"(19|20)\d{2}"#, options: .regularExpression).map { String(citation[$0]) } ?? ""
        if id == "mgh" { return "Mass General Brigham protocol" }
        if id == "gamesNote" { return "JOSPT 2021 (games)" }
        let many = citation.contains("et al") || citation.components(separatedBy: ",").count > 3
        return "\(author)\(many ? " et al." : "") \(year)".trimmingCharacters(in: .whitespaces)
    }
}

enum EvidenceLibrary {
    static let all: [Evidence] = [
        Evidence(id: "jospt2021",
                 citation: "Martin RL, et al. Ankle Stability and Movement Coordination Impairments: Lateral Ankle Ligament Sprains Revision 2021. J Orthop Sports Phys Ther. 2021;51(4):CPG1–CPG80.",
                 finding: "Grade A: progressive weight bearing with external support, and structured exercise including balance training, in clinic and at home. Grade A: balance-focused exercise plus bracing after a first sprain.",
                 url: "https://www.jospt.org/doi/10.2519/jospt.2021.0302"),
        Evidence(id: "vuurberg2018",
                 citation: "Vuurberg G, et al. Diagnosis, treatment and prevention of ankle sprains: update of an evidence-based clinical guideline. Br J Sports Med. 2018;52(15):956.",
                 finding: "Functional treatment (exercise and support) is preferred over immobilisation; exercise therapy should start early.",
                 url: "https://bjsm.bmj.com/content/52/15/956"),
        Evidence(id: "hupperets2009",
                 citation: "Hupperets MDW, Verhagen EALM, van Mechelen W. Effect of unsupervised home based proprioceptive training on recurrences of ankle sprain: randomised controlled trial. BMJ. 2009;339:b2684.",
                 finding: "An 8-week home balance programme (3×/week) reduced re-sprains from 33% to 22% (RR 0.63; NNT 9). Only 23% fully complied, which is the problem this app targets.",
                 url: "https://www.bmj.com/content/339/bmj.b2684"),
        Evidence(id: "peacelove",
                 citation: "Dubois B, Esculier JF. Soft-tissue injuries simply need PEACE and LOVE. Br J Sports Med. 2020;54(2):72–73.",
                 finding: "Protect, Elevate, Avoid anti-inflammatories, Compress, Educate; then Load, Optimism, Vascularisation, Exercise.",
                 url: "https://bjsm.bmj.com/content/54/2/72"),
        Evidence(id: "doherty2017",
                 citation: "Doherty C, et al. Treatment and prevention of acute and recurrent ankle sprain: an overview of systematic reviews with meta-analysis. Br J Sports Med. 2017;51(2):113–125.",
                 finding: "Exercise therapy and bracing reduce recurrence; supervised and home exercise both help.",
                 url: "https://bjsm.bmj.com/content/51/2/113"),
        Evidence(id: "doherty2016",
                 citation: "Doherty C, et al. Recovery from a first-time lateral ankle sprain and the predictors of chronic ankle instability. Am J Sports Med. 2016;44(4):995–1003.",
                 finding: "About 40% of people developed chronic ankle instability within a year of a first sprain.",
                 url: "https://doi.org/10.1177/0363546516628870"),
        Evidence(id: "ottawa",
                 citation: "Stiell IG, et al. Decision rules for the use of radiography in acute ankle injuries. JAMA. 1993;269(9):1127–1132.",
                 finding: "The Ottawa Ankle Rules identify who needs an X-ray, with sensitivity close to 100% for fractures.",
                 url: "https://jamanetwork.com/journals/jama/fullarticle/404765"),
        Evidence(id: "sylcott2021",
                 citation: "Sylcott B, et al. Investigating the Use of Virtual Reality Headsets for Postural Control Assessment: Instrument Validation Study. JMIR Rehabil Assist Technol. 2021;8(4):e24950.",
                 finding: "Headset-tracked RMS sway is related to force-plate sway, so the app reports steadiness as an experimental training score, not a diagnosis.",
                 url: "https://rehab.jmir.org/2021/4/e24950"),
        Evidence(id: "mgh",
                 citation: "Mass General Brigham Sports Physical Therapy. Rehabilitation Protocol for Ankle Sprain (phases I–IV).",
                 finding: "Phase III adds dual-task balance (ball toss with a smaller base of support or an unstable surface), double-leg hopping, lateral bounding and agility-ladder drills. Single-leg hopping starts in phase IV, after 25 single-leg heel raises (or equal to the other side), ≥80% Y-balance and good patient-reported scores.",
                 url: "https://www.massgeneralbrigham.org/content/dam/unified-xwalk/pdf/patient-education/english/rehabilitation-protocol-for-ankle-sprain.pdf"),
        Evidence(id: "paass2021",
                 citation: "Smith MD, Vicenzino B, Bahr R, et al. Return to sport decisions after an acute lateral ankle sprain injury: introducing the PAASS framework. Br J Sports Med. 2021;55(22):1270–1276.",
                 finding: "Return to sport should consider Pain, Ankle impairments, Athlete perception (confidence), Sensorimotor control and Sport/functional performance (hopping, jumping, agility), decided together with the athlete.",
                 url: "https://bjsm.bmj.com/content/55/22/1270"),
        Evidence(id: "iac2014",
                 citation: "Gribble PA, Delahunt E, Bleakley C, et al. Selection criteria for patients with chronic ankle instability: a position statement of the International Ankle Consortium. J Athl Train. 2014;49(1):121–127.",
                 finding: "Chronic ankle instability: a previous significant sprain, plus repeated 'giving way', recurrent sprains or feelings of instability. Such patients need longer, balance-focused rehab.",
                 url: "https://doi.org/10.4085/1062-6050-49.1.14"),
        Evidence(id: "lin2021",
                 citation: "Lin H, Han K, Ruan B. Effect of virtual reality on functional ankle instability rehabilitation: a systematic review. J Healthc Eng. 2021:7363403.",
                 finding: "Across 5 RCTs (137 people), VR rehab beat conventional training on 30-second single-leg stance and joint position sense. Evidence is still limited.",
                 url: "https://doi.org/10.1155/2021/7363403"),
        Evidence(id: "nhs111",
                 citation: "NHS 111 Wales. Sprains and strains (self-care advice).",
                 finding: "For the first 2–3 days avoid heat (hot baths, heat packs), alcohol and massage to limit swelling. Protect, rest, ice in short sessions, compress and elevate.",
                 url: "https://111.wales.nhs.uk/sprainsandstrains/"),
        Evidence(id: "bodyparts3d",
                 citation: "Mitsuhashi N, et al. BodyParts3D: 3D structure database for anatomical concepts. Nucleic Acids Res. 2009;37:D782–D785.",
                 finding: "Source of the 3D bones, muscles and tendons in Motial's ankle model (CC BY-SA 2.1 JP).",
                 url: "https://doi.org/10.1093/nar/gkn613"),
        Evidence(id: "falls2022",
                 citation: "Montero-Odasso M, van der Velde N, Martin FC, et al. World guidelines for falls prevention and management for older adults: a global initiative. Age Ageing. 2022;51(9):afac205.",
                 finding: "A fall in the past year marks higher falls risk. Balance and functional exercise is recommended, done safely and progressed gradually.",
                 url: "https://doi.org/10.1093/ageing/afac205"),
        Evidence(id: "mcguine2006",
                 citation: "McGuine TA, Keene JS. The effect of a balance training program on the risk of ankle sprains in high school athletes. Am J Sports Med. 2006;34(7):1103–1111.",
                 finding: "In a randomised trial of 765 basketball and soccer players, balance training lowered ankle sprains from 9.9% to 6.1%.",
                 url: "https://doi.org/10.1177/0363546505284191"),
        Evidence(id: "mckay2001",
                 citation: "McKay GD, Goldie PA, Payne WR, Oakes BW. Ankle injuries in basketball: injury rate and risk factors. Br J Sports Med. 2001;35(2):103–108.",
                 finding: "Ankle injuries were the most common basketball injury, and landing on another player's foot was the most common way they happened.",
                 url: "https://bjsm.bmj.com/content/35/2/103"),
        Evidence(id: "okazaki2012",
                 citation: "Okazaki VHA, Rodacki ALF. Increased distance of shooting on basketball jump shot. J Sports Sci Med. 2012;11(2):231–237.",
                 finding: "Shots released near the top of the rise, from a stable base, were the most accurate; the legs drive the ball and the arm finishes the release.",
                 url: "https://www.jssm.org/jssm-11-231.xml-Fulltext"),
        Evidence(id: "fong2023",
                 citation: "Fong DTP, Mok KM, Thompson IM, Wang HY, King MA. A lateral ankle sprain during a lateral backward step in badminton: a case report of a televised injury incident. J Sport Health Sci. 2023;12(1):139–144.",
                 finding: "The sprain followed a forefoot landing with the ankle pointed down and turned in during a sideways-backward step; prevention should train control of the ankle on forefoot landings.",
                 url: "https://doi.org/10.1016/j.jshs.2021.03.007"),
        Evidence(id: "fu2017",
                 citation: "Fu L, Ren F, Baker JS. Comparison of joint loading in badminton lunging between professional and amateur badminton players. Appl Bionics Biomech. 2017;2017:5397656.",
                 finding: "Amateurs landed the lunge with more side-to-side ankle movement and inversion load than professionals; correct foot landing in the lunge and peroneal strength are recommended.",
                 url: "https://doi.org/10.1155/2017/5397656"),
        Evidence(id: "donath2025",
                 citation: "Stepper B, Hecksteden A, Stagge H, Faude O, Donath L. Systematic review on badminton injuries: incidence, characteristics and risk factors. BMJ Open Sport Exerc Med. 2025;11(1):e002127.",
                 finding: "Most badminton injuries are in the lower body (41–92%), from rapid accelerations, decelerations and changes of direction; incidence about 1–4 per 1000 hours.",
                 url: "https://doi.org/10.1136/bmjsem-2024-002127"),
        Evidence(id: "ulrich1984",
                 citation: "Ulrich RS. View through a window may influence recovery from surgery. Science. 1984;224(4647):420–421.",
                 finding: "Patients whose room looked out on trees needed fewer strong painkillers and went home sooner than those facing a wall.",
                 url: "https://doi.org/10.1126/science.6143402"),
        Evidence(id: "williams2010",
                 citation: "Williams GN, Allen EJ. Rehabilitation of syndesmotic (high) ankle sprains. Sports Health. 2010;2(6):460–470.",
                 finding: "High ankle sprains take longer to recover than outer sprains; rehab progresses more slowly and avoids twisting the foot outward and deep ankle bending early.",
                 url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC3438867"),
        Evidence(id: "deltoidNCH",
                 citation: "Nationwide Children's Hospital Sports Medicine. Deltoid ligament sprain (patient guide).",
                 finding: "Inner (deltoid) sprains happen when the ankle rolls outward, are much less common, and can come with a high ankle sprain; rehab restores motion, strength and balance.",
                 url: "https://www.nationwidechildrens.org/conditions/sports-medicine-deltoid-ligament-sprain"),
        Evidence(id: "gamesNote",
                 citation: "Martin RL, et al. (JOSPT 2021 CPG), recommendation on augmenting home programmes with apps or exercise video games: Grade D (conflicting evidence).",
                 finding: "Games in this app deliver the guideline exercises; they don't replace them.",
                 url: "https://www.jospt.org/doi/10.2519/jospt.2021.0302"),
    ]
    static func byID(_ id: String) -> Evidence? { all.first { $0.id == id } }
}

// MARK: - Muscles working & what each exercise helps you do

struct MuscleInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let role: String
    let anatomyKey: String?         // structure in the 3D ankle that can be lit up
}

enum MuscleLibrary {
    static let fibularis = MuscleInfo(name: "Fibularis (peroneals)", role: "stops the ankle rolling outward", anatomyKey: "fibularis_longus")
    static let tibAnt = MuscleInfo(name: "Tibialis anterior", role: "lifts the foot and toes", anatomyKey: "tibialis_anterior")
    static let tibPost = MuscleInfo(name: "Tibialis posterior", role: "supports the arch and inner ankle", anatomyKey: nil)
    static let calf = MuscleInfo(name: "Calf (gastrocnemius & soleus)", role: "pushes off and absorbs landings", anatomyKey: "achilles_tendon")
    static let footIntrinsics = MuscleInfo(name: "Small foot muscles", role: "fine-tune balance through the toes", anatomyKey: nil)
    static let gluteMed = MuscleInfo(name: "Gluteus medius (hip)", role: "keeps the pelvis level on one leg", anatomyKey: nil)
    static let quads = MuscleInfo(name: "Quadriceps", role: "controls the knee as you bend and land", anatomyKey: nil)
    static let gluteMax = MuscleInfo(name: "Gluteus maximus", role: "powers squats, hops and stairs", anatomyKey: nil)
    static let core = MuscleInfo(name: "Core", role: "keeps the trunk steady when you reach", anatomyKey: nil)

    static let byExercise: [String: [MuscleInfo]] = [
        "ankle_pumps": [tibAnt, calf],
        "ankle_alphabet": [tibAnt, fibularis, tibPost, calf],
        "seated_eversion": [fibularis],
        "seated_inversion": [tibPost],
        "calf_raise": [calf, fibularis],
        "lantern_glide": [calf, fibularis],
        "lantern_glide_seated": [tibAnt, calf],
        "dawn_drive": [calf, fibularis, tibAnt],
        "dawn_drive_seated": [tibAnt, calf],
        "dawn_drive_cockpit": [tibAnt, calf],
        "knee_to_wall": [calf, tibAnt],
        "supported_sls": [fibularis, tibPost, footIntrinsics, gluteMed],
        "single_leg_stance": [fibularis, tibPost, footIntrinsics, gluteMed],
        "sls_head_turns": [fibularis, tibPost, footIntrinsics, gluteMed],
        "sls_reach_catch": [fibularis, tibPost, gluteMed, core],
        "sl_mini_squat": [quads, gluteMed, gluteMax, fibularis],
        "sl_calf_raise": [calf, fibularis, tibPost],
        "stepping_stones": [fibularis, tibAnt, tibPost, gluteMed],
        "rhythm_steps": [fibularis, calf, gluteMed],
        "hop_forward": [calf, quads, gluteMax, fibularis],
        "side_hop": [fibularis, gluteMed, calf],
        "river_hops": [calf, fibularis, quads, gluteMax],
    ]

    /// Everyday and sport activities each exercise builds toward.
    static let unlocks: [String: [String]] = [
        "ankle_pumps": ["Less swelling and stiffness, so first steps feel easier"],
        "ankle_alphabet": ["Full ankle movement for walking and stairs"],
        "seated_eversion": ["Catching your ankle before it rolls on uneven ground or a kerb"],
        "seated_inversion": ["Supporting your arch when you walk and stand for longer"],
        "calf_raise": ["Normal push-off when walking", "Climbing stairs", "Standing on tiptoe to reach a shelf"],
        "dawn_drive": ["Smooth push-off when walking", "Controlled stepping down stairs"],
        "dawn_drive_cockpit": ["Moving the ankle freely again", "Smooth control of the foot"],
        "dawn_drive_seated": ["Moving the ankle freely again", "Less stiffness after sitting"],
        "lantern_glide_seated": ["Moving the ankle freely again", "Less stiffness after sitting"],
        "lantern_glide": ["Smooth push-off when walking", "Climbing stairs", "Standing on tiptoe with control"],
        "knee_to_wall": ["Walking downstairs and down slopes", "Squatting down without the ankle blocking"],
        "supported_sls": ["Standing on one leg to put on trousers and shoes", "Stepping onto a bus or train"],
        "single_leg_stance": ["Steady walking on uneven paths", "Fewer re-sprains"],
        "sls_head_turns": ["Looking around while walking in crowds or crossing the road"],
        "sls_reach_catch": ["Reaching, catching and reacting without losing balance, in sport and daily life"],
        "sl_mini_squat": ["Going down stairs and kerbs with control", "Landing softly"],
        "sl_calf_raise": ["Jogging and running (25 heel raises is a common return-to-run check)", "Stairs two at a time"],
        "stepping_stones": ["Walking over uneven ground, grass and hiking paths"],
        "rhythm_steps": ["Quick changes of direction: dodging people, dancing, court footwork"],
        "hop_forward": ["Jogging and running", "Jumping in sport"],
        "side_hop": ["Side-to-side sports: badminton, basketball, football"],
        "river_hops": ["Hopping and landing on one leg with confidence, the last step before sport"],
    ]
}

extension Exercise {
    var muscles: [MuscleInfo] { MuscleLibrary.byExercise[id] ?? [] }
    var unlocks: [String] { MuscleLibrary.unlocks[id] ?? [] }
    var musclesSpoken: String {
        let names = muscles.map(\.name)
        guard !names.isEmpty else { return "" }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
        return "This works your \(list)." + (unlocks.first.map { " It helps with: \($0.lowercased())." } ?? "")
    }
}

extension ExerciseKind {
    var isGame: Bool { if case .game = self { return true } else { return false } }
    /// Games where the ankle is the accelerator (heel raise standing, Motial Pedal iPhone seated).
    var isPedalGame: Bool {
        if case .game(let g) = self { return g == .lanternGlide || g == .dawnDrive || g == .cockpitDrive }
        return false
    }
}
