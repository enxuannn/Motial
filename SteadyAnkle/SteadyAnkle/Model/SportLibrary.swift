import Foundation

// MARK: - Return to Sport ("Sport Lab")
//
// Athletes who sprained an ankle relearn the movements of their sport with the right technique:
// a 360° / spatial video of a real person demonstrating it, and the life-size 3D coach doing the drill
// in an immersive court. Drills follow the same safety rules as the rest of Steady: stage-gated,
// hops and jumps only with clinician clearance (MGH phase IV, PAASS 2021), never for people with fall risk.

enum Sport: String, Codable, CaseIterable, Identifiable {
    case basketball, badminton, football
    var id: String { rawValue }
    var title: String {
        switch self {
        case .basketball: return "Basketball"
        case .badminton: return "Badminton"
        case .football: return "Football"
        }
    }
    var symbol: String {
        switch self {
        case .basketball: return "figure.basketball"
        case .badminton: return "figure.badminton"
        case .football: return "figure.soccer"
        }
    }
}

/// Floor targets the coach and the person step on, in metres relative to the person (x right, z forward = negative).
struct FootworkMark: Equatable {
    let x: Float
    let z: Float
    let beat: Double          // seconds into the drill when this mark lights up
    let hop: Bool             // landing (true) or step (false)
}

struct SportDrill: Identifiable, Equatable {
    let id: String
    let sport: Sport
    let title: String
    let symbol: String
    let stages: ClosedRange<Int>
    let requiresHopClearance: Bool
    let clip: String                  // coach animation clip (CoachRig), without side suffix
    let dosage: Dosage
    let technique: [String]           // the correct technique, step by step (shown and spoken)
    let commonMistakes: [String]      // what puts the ankle at risk
    let marks: [FootworkMark]         // footwork pattern shown on the floor
    let ballToHoop: Bool              // show the ball arcing into the hoop at the end of each rep
    let evidence: [String]
    /// A filmed demonstration bundled with the app ("video_<id>.mov", 180°/360° APMP or spatial video),
    /// or one the physio/coach adds in Sport Lab (stored per drill id, like clinician exercise videos).
    var videoKey: String { id }

    func fits(_ stage: RehabStage) -> Bool { stages.contains(stage.rawValue) }
}

enum SportLibrary {
    static let all: [SportDrill] = [
        SportDrill(id: "bb_set_shot", sport: .basketball, title: "Balanced Set Shot", symbol: "basketball",
                   stages: 3...4, requiresHopClearance: false, clip: "set_shot",
                   dosage: Dosage(sets: 3, reps: 8, restSeconds: 40),
                   technique: ["Balance: feet shoulder-width, shooting foot slightly ahead, toes to the rim.",
                               "Dip: bend the knees and hips together, knees over the toes, ball in the shooting pocket.",
                               "Rise: the legs drive the ball up, elbow under the ball, release at the top and snap the wrist.",
                               "Hold the follow-through on the balls of your feet, then lower your heels slowly."],
                   commonMistakes: ["Landing on the outside edge of the foot", "Knees collapsing inward", "Feet drifting apart on the finish"],
                   marks: [FootworkMark(x: -0.15, z: 0, beat: 0, hop: false), FootworkMark(x: 0.15, z: -0.08, beat: 0, hop: false)],
                   ballToHoop: true, evidence: ["okazaki2012", "jospt2021", "paass2021", "mcguine2006"]),
        SportDrill(id: "bb_jump_stop", sport: .basketball, title: "Jump Stop & Stick", symbol: "arrow.down.to.line",
                   stages: 4...4, requiresHopClearance: true, clip: "hop_forward",
                   dosage: Dosage(sets: 3, reps: 5, restSeconds: 60),
                   technique: ["Take two easy steps forward.", "Hop off one foot and land on both feet at the same time.",
                               "Land quietly: hips back, knees soft and over the toes.", "Stick the landing for two seconds, then reset."],
                   commonMistakes: ["Stiff-legged, loud landings", "Rolling onto the outside of the ankle", "Knees caving in on landing"],
                   marks: [FootworkMark(x: 0, z: -0.5, beat: 0.6, hop: false), FootworkMark(x: 0, z: -1.0, beat: 1.2, hop: false),
                           FootworkMark(x: 0, z: -1.6, beat: 1.9, hop: true)],
                   ballToHoop: false, evidence: ["mgh", "paass2021", "jospt2021", "mckay2001"]),
        SportDrill(id: "bb_defensive_slide", sport: .basketball, title: "Defensive Slide", symbol: "arrow.left.and.right",
                   stages: 3...4, requiresHopClearance: false, clip: "step_beat",
                   dosage: Dosage(sets: 3, reps: 6, restSeconds: 45),
                   technique: ["Athletic stance: feet wider than the shoulders, hips low, chest up.",
                               "Step with the lead foot, then bring the trail foot after it. Never cross the feet.",
                               "Push off the inside of the trail foot and keep the toes pointing forward.",
                               "Three slides each way, then return to the centre."],
                   commonMistakes: ["Crossing the feet", "Standing up tall between slides", "Turning the toes out and rolling the ankle"],
                   marks: [FootworkMark(x: 0.5, z: 0, beat: 0.8, hop: false), FootworkMark(x: 1.0, z: 0, beat: 1.6, hop: false),
                           FootworkMark(x: 0.5, z: 0, beat: 2.6, hop: false), FootworkMark(x: 0, z: 0, beat: 3.4, hop: false),
                           FootworkMark(x: -0.5, z: 0, beat: 4.2, hop: false), FootworkMark(x: -1.0, z: 0, beat: 5.0, hop: false)],
                   ballToHoop: false, evidence: ["jospt2021", "mgh", "mcguine2006"]),
        SportDrill(id: "bb_layup_footwork", sport: .basketball, title: "Layup Footwork", symbol: "figure.basketball",
                   stages: 4...4, requiresHopClearance: true, clip: "hop_forward",
                   dosage: Dosage(sets: 3, reps: 4, restSeconds: 60),
                   technique: ["Right-handed layup: step right, then left.", "Drive up off the left foot, right knee lifting toward the hoop.",
                               "Land on both feet, soft and balanced, under control.", "Walk back and repeat. Left-handed: mirror the steps."],
                   commonMistakes: ["Taking off from the wrong foot", "Landing on one foot", "Drifting sideways in the air"],
                   marks: [FootworkMark(x: 0.25, z: -0.6, beat: 0.7, hop: false), FootworkMark(x: -0.15, z: -1.3, beat: 1.4, hop: false),
                           FootworkMark(x: 0, z: -1.9, beat: 2.2, hop: true)],
                   ballToHoop: true, evidence: ["mgh", "paass2021", "mckay2001"]),

        // Badminton (28 Oct). Most badminton injuries are in the lower body (Donath et al. 2025); sprains follow forefoot
        // landings with the ankle pointed and turned in, in sideways-backward steps and lunges (Fong et al. 2023;
        // Fu et al. 2017). Drills train the two footwork moves every rally is built on, with the landing done right.
        SportDrill(id: "bd_front_lunge", sport: .badminton, title: "Net Lunge & Recover", symbol: "figure.badminton",
                   stages: 3...4, requiresHopClearance: false, clip: "bd_lunge",
                   dosage: Dosage(sets: 3, reps: 6, restSeconds: 45),
                   technique: ["Ready stance: feet shoulder-width, knees soft, racket up in front.",
                               "Step out with your racket-side foot toward the front corner, heel first, then the whole foot.",
                               "Toes and knee point at the shuttle, the knee stays over the foot, the back foot stays down.",
                               "Push back through the front heel to your base, then reset."],
                   commonMistakes: ["Landing on the toes or the outside edge of the foot", "Front foot turned out or in",
                                    "Knee collapsing inward", "Lunging too long at first"],
                   marks: [FootworkMark(x: 0, z: 0, beat: 0, hop: false), FootworkMark(x: 0.18, z: -0.75, beat: 1.0, hop: false),
                           FootworkMark(x: 0, z: 0, beat: 1.6, hop: false)],
                   ballToHoop: false, evidence: ["fu2017", "donath2025", "jospt2021", "mgh"]),
        SportDrill(id: "bd_split_step", sport: .badminton, title: "Split Step & Soft Landing", symbol: "arrow.up.and.down.and.arrow.left.and.right",
                   stages: 4...4, requiresHopClearance: true, clip: "bd_split",
                   dosage: Dosage(sets: 3, reps: 6, restSeconds: 60),
                   technique: ["Ready stance, weight on the balls of the feet.",
                               "As the opponent hits, make a small hop off both feet.",
                               "Land a little wider on the balls of both feet, knees soft and over the toes.",
                               "Settle, stay balanced, then reset."],
                   commonMistakes: ["Big, high hops", "Landing on one foot", "Ankles rolling outward on the landing"],
                   marks: [FootworkMark(x: -0.22, z: 0, beat: 0.8, hop: true), FootworkMark(x: 0.22, z: 0, beat: 0.8, hop: true)],
                   ballToHoop: false, evidence: ["fong2023", "paass2021", "mgh", "jospt2021"]),
    ]

    static func byID(_ id: String) -> SportDrill? { all.first { $0.id == id } }
    static func drills(for sport: Sport) -> [SportDrill] { all.filter { $0.sport == sport } }
}

extension ClinicalEngine {
    enum DrillAccess: Equatable {
        case open
        case locked(String)            // reason shown to the person
    }

    /// Same safety rules as hopping in the main plan: stage first, then clinician clearance, low pain and good confidence.
    static func access(_ d: SportDrill, profile p: PatientProfile, stage: RehabStage, latestPain: Int, confidence: Int) -> DrillAccess {
        if case .seeClinicianFirst = triage(p) { return .locked("See a clinician first.") }
        if p.fallRisk && d.requiresHopClearance { return .locked("Jumps stay switched off because of fall risk.") }
        guard d.fits(stage) else {
            return .locked("Unlocks in Stage \(d.stages.lowerBound): \(RehabStage(rawValue: d.stages.lowerBound)?.title ?? "").")
        }
        if d.requiresHopClearance {
            if !hopsAllowed(p) { return .locked("Needs your physiotherapist's OK for jumping (Settings → Clinician).") }
            if latestPain > 1 || confidence < 4 { return .locked("Jumping drills open on days with pain 0–1/10 and confidence 4/5 or more.") }
        }
        if latestPain >= 4 { return .locked("Pain is \(latestPain)/10 today. Rest the drills and do your plan instead.") }
        return .open
    }

    /// Return to Sport shows up for people whose goal is sport, from Stage 3.
    static func showsSportLab(_ p: PatientProfile?, stage: RehabStage) -> Bool {
        guard let p else { return false }
        return p.goal == .courtSports || stage >= .balance
    }
}
