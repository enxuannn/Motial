import Foundation

/// Court Smarts: what a healing ankle can and cannot do on a basketball court, shown with real footage
/// (Mixkit, free licence) on an immersive court, a live 3D ankle that shows why, and a verdict for *you today*.
///
/// Evidence used for the wording:
/// • Landing on another player's foot is the most common way basketball players sprain an ankle (McKay et al.,
///   Br J Sports Med 2001). The sprain mechanism is inversion with plantarflexion, which loads the anterior
///   talofibular ligament (ATFL) first, then the calcaneofibular ligament (CFL).
/// • Healing ligaments take months to regain strength, and re-sprain risk is highest in the first year;
///   return to cutting and jumping should be gradual and criteria-based (JOSPT Clinical Practice Guideline 2021).
/// • External support (brace or tape) reduces recurrence when returning to sport (JOSPT CPG 2021).
struct CourtMove: Identifiable, Equatable {
    enum Verdict: String { case safe, care, notYet }
    let id: String
    let title: String
    let video: String              // bundled clip, without extension
    let verdict: Verdict
    let opensAt: RehabStage        // the stage where this move becomes appropriate
    let needsJumpClearance: Bool   // also needs the physiotherapist's OK for jumping
    let why: String                // the ankle reason, one or two short sentences
    let instead: String            // what to do instead / how to do it safely
    let plantar: Float             // 3D ankle demo: toes-down 0…1
    let inversion: Float           // 3D ankle demo: rolling in 0…1
    /// Rendered 180° scenes on Sunset Court (Blender, the app's own coach Maya and Alex), watched life-size around you.
    var scenes180: [Clip180] = []
    var evidence: [String] { CourtGuide.evidenceByMove[id] ?? ["jospt2021"] }
}

struct Clip180: Equatable {
    let label: String
    let video: String
    let line: String
    /// Frames (24 fps) of this scene inside Court3D.usdz, the live 3D version: real stereo depth and walk-around
    /// parallax, played on Sunset Court. Built by Tools/AssetPipeline/bake_court3d.py. nil = video only.
    var frames: ClosedRange<Int>? = nil
}

/// The sport or everyday activity Play Smart is tailored to (asked on the card, saved in the profile).
enum PlaySport: String, Codable, CaseIterable, Identifiable {
    case basketball, badminton, football, running, everyday
    var id: String { rawValue }
    var title: String {
        switch self {
        case .basketball: return "Basketball"
        case .badminton: return "Badminton"
        case .football: return "Football"
        case .running: return "Running"
        case .everyday: return "Everyday life"
        }
    }
    /// Short name for the sport picker on the Today card.
    var shortTitle: String { self == .everyday ? "Everyday" : title }
    var symbol: String {
        switch self {
        case .basketball: return "figure.basketball"
        case .badminton: return "figure.badminton"
        case .football: return "figure.soccer"
        case .running: return "figure.run"
        case .everyday: return "figure.walk"
        }
    }
    /// A real moment from each sport (frames of the bundled Mixkit clips), so every sport has its own picture.
    var cover: String { "cover_play_\(rawValue)" }
    var subtitle: String {
        switch self {
        case .everyday: return "Stairs, kerbs, rushing, shoes: what is safe for your ankle now, what needs care, and why."
        default: return "Real \(title.lowercased()) footage: which moves are safe while you heal, which need care, which wait, and what each does to your ankle."
        }
    }
    var welcome: String {
        switch self {
        case .basketball: return "Welcome to Play Smart for basketball. See what each move does to your ankle."
        case .badminton: return "Welcome to Play Smart for badminton. See what each move does to your ankle."
        case .football: return "Welcome to Play Smart for football. See what each move does to your ankle."
        case .running: return "Welcome to Play Smart for running. See what each surface does to your ankle."
        case .everyday: return "Welcome to Move Smart. See what everyday moments do to your ankle."
        }
    }
    /// Best guess before the person chooses: from the goal they set in onboarding.
    static func suggested(for p: PatientProfile?) -> PlaySport {
        if let s = p?.playSport { return s }
        switch p?.goal {
        case .courtSports: return .basketball
        case .running: return .running
        default: return .everyday
        }
    }
}

enum CourtGuide {
    static func moves(for sport: PlaySport) -> [CourtMove] {
        switch sport {
        case .basketball: return basketball
        case .badminton: return badminton
        case .football: return football
        case .running: return running
        case .everyday: return everyday
        }
    }

    // Badminton: most injuries are in the lower body, from rapid stops and changes of direction (Donath et al., BMJ Open
    // Sport Exerc Med 2025); sprains follow forefoot landings with the ankle pointed and turned in during sideways-backward
    // steps (Fong et al., J Sport Health Sci 2023) and lunges with poor foot placement (Fu et al., Appl Bionics Biomech 2017).
    static let badminton: [CourtMove] = [
        CourtMove(id: "bm_rally", title: "Rallies from the middle of the court", video: "video_bm_rally", verdict: .safe,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Short steps with both feet under you keep the ankle upright while you swing.",
                  instead: "Stay near the centre, use small split-steps, and return to base between shots.",
                  plantar: 0.2, inversion: 0.05),
        CourtMove(id: "bm_shuffle", title: "Side shuffles to cover the court", video: "video_bm_play", verdict: .care,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Quick sideways pushes load the outer ankle. Crossing your feet or landing on the outside edge tips the foot inward.",
                  instead: "Small chassé steps, feet never cross, push from the inside of the foot.",
                  plantar: 0.2, inversion: 0.4),
        CourtMove(id: "bm_lunge", title: "Lunging for a net shot", video: "video_bm_rally", verdict: .care,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "A deep lunge lands hard on the front heel. If the foot turns out or rolls, the ankle twists under you.",
                  instead: "Short lunges first, toes and knee pointing at the shuttle, heel then flat foot.",
                  plantar: 0.35, inversion: 0.35),
        CourtMove(id: "bm_smash", title: "Jump smash landings", video: "video_bm_play", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: true,
                  why: "A jump smash often lands on one foot while you turn, rolling the foot inward under your full body weight.",
                  instead: "Smash from the ground first. Once cleared to jump, land on both feet facing the net.",
                  plantar: 0.6, inversion: 0.9),
        CourtMove(id: "bm_scissor", title: "Scissor kick in the back court", video: "video_bm_rally", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: true,
                  why: "Switching legs in the air means landing on one foot while moving backwards, when the ankle is least stable.",
                  instead: "Move back with shuffle steps and play the clear without the jump.",
                  plantar: 0.55, inversion: 0.7),
    ]

    // Football: most ankle sprains come from player contact and tackles (Woods et al., Br J Sports Med 2003).
    static let football: [CourtMove] = [
        CourtMove(id: "fb_pass", title: "Short passes, standing still", video: "video_fb_passing", verdict: .safe,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "The standing foot stays flat while the inside of the other foot strikes the ball gently.",
                  instead: "Pass with the inside of the foot, standing foot pointing at your target.",
                  plantar: 0.1, inversion: 0.1),
        CourtMove(id: "fb_shoot", title: "Shooting and long kicks", video: "video_fb_shot", verdict: .care,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Your full weight goes through the standing ankle as you strike hard. A heavy plant can roll it.",
                  instead: "Plant the standing foot flat beside the ball, toes forward, and build power slowly.",
                  plantar: 0.3, inversion: 0.3),
        CourtMove(id: "fb_penalty", title: "Penalties and set pieces", video: "video_fb_penalty", verdict: .care,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "One hard strike after a run-up, but no one around you, so you control the landing.",
                  instead: "Shorter run-up and a balanced finish on the standing foot.",
                  plantar: 0.3, inversion: 0.25),
        CourtMove(id: "fb_cut", title: "Cutting and quick turns", video: "video_fb_match", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Planting and turning on studs twists the foot inward while it is stuck in the grass.",
                  instead: "Practise wide, slow curves before sharp cuts, and tape or brace when you return.",
                  plantar: 0.3, inversion: 0.75),
        CourtMove(id: "fb_tackle", title: "Tackles and 50-50 challenges", video: "video_fb_oneonone", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Most football ankle sprains come from contact: a tackle or another player's foot forces the ankle to roll over.",
                  instead: "Avoid contact play until your physiotherapist clears you, then brace or tape.",
                  plantar: 0.5, inversion: 1.0),
    ]

    // Running: uneven ground is the classic cause; return gradually on flat ground first (JOSPT CPG 2021).
    static let running: [CourtMove] = [
        CourtMove(id: "run_flat", title: "Easy jogging on a flat track", video: "video_run_track", verdict: .care,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Flat, even ground lands every step the same way, so the ankle never has to catch a roll.",
                  instead: "Start with walk-jog intervals of a few minutes. Stop if the ankle swells the next day.",
                  plantar: 0.3, inversion: 0.05),
        CourtMove(id: "run_path", title: "Park paths and gentle trails", video: "video_run_trail", verdict: .care,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Small bumps and roots tilt the foot on every step, so the muscles on the outside of the ankle must react fast.",
                  instead: "Add paths only after flat running is pain-free. Shorter steps, eyes ahead.",
                  plantar: 0.3, inversion: 0.35),
        CourtMove(id: "run_trail", title: "Forest and rocky trails", video: "video_run_forest", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Rocks and holes can drop the foot into a roll before you can react. This is how most running sprains happen.",
                  instead: "Wait until hopping and single-leg balance feel strong, and wear a brace at first.",
                  plantar: 0.4, inversion: 0.8),
        CourtMove(id: "run_down", title: "Downhill running and sprints", video: "video_run_track", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Downhill and sprinting land with the toes pointed down, the ankle's loosest, least stable position.",
                  instead: "Keep to flat, easy runs, and add hills and speed gradually over weeks.",
                  plantar: 0.7, inversion: 0.4),
    ]

    // Everyday life: stairs, kerbs and shoes (PEACE & LOVE; JOSPT CPG 2021: early protected walking is encouraged).
    static let everyday: [CourtMove] = [
        CourtMove(id: "ev_up", title: "Climbing stairs", video: "video_ev_stairs_up", verdict: .care,
                  opensAt: .protect, needsJumpClearance: false,
                  why: "Each step up pushes through the ankle, and a sore ankle may wobble on a narrow step.",
                  instead: "Hold the rail. Going up, lead with your good foot.",
                  plantar: 0.3, inversion: 0.1),
        CourtMove(id: "ev_down", title: "Going down stairs", video: "video_ev_stairs_down", verdict: .care,
                  opensAt: .protect, needsJumpClearance: false,
                  why: "Stepping down lands on the front of the foot with the toes pointed, where the ankle rolls most easily.",
                  instead: "Hold the rail. Going down, lead with your injured foot, one step at a time.",
                  plantar: 0.5, inversion: 0.3),
        CourtMove(id: "ev_rush", title: "Rushing for the bus or train", video: "video_ev_rush", verdict: .notYet,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Hurrying means quick, unplanned steps and kerbs you don't see.",
                  instead: "Leave a few minutes earlier and walk at a steady pace.",
                  plantar: 0.4, inversion: 0.5),
        CourtMove(id: "ev_heels", title: "High heels", video: "video_ev_heels", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "Heels hold the foot pointed down, the ankle's loosest position, on a tiny base. A small tilt becomes a roll.",
                  instead: "Choose flat, supportive shoes that lace up for now.",
                  plantar: 0.8, inversion: 0.5),
    ]

    static let basketball: [CourtMove] = [
        CourtMove(id: "shoot", title: "Shooting from your stance", video: "video_bb_set_shot", verdict: .safe,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Both feet planted and weight even: the ankle stays upright, so the healing ligament is barely stretched.",
                  instead: "Rise onto both toes and land your finish on both feet.",
                  plantar: 0.45, inversion: 0.0),
        CourtMove(id: "dribble", title: "Dribbling on the spot", video: "video_court_dribble", verdict: .safe,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Feet flat and wide apart. The muscles on the outside of your ankle hold it steady.",
                  instead: "Keep your feet still and your knees soft while the ball moves.",
                  plantar: 0.1, inversion: 0.08),
        CourtMove(id: "defend", title: "Guarding and side steps", video: "video_court_defend", verdict: .care,
                  opensAt: .balance, needsJumpClearance: false,
                  why: "Side steps load the outer ankle. Crossing your feet or turning the toes out can tip the foot inward.",
                  instead: "Small steps, toes forward, never cross your feet. Short sets only.",
                  plantar: 0.2, inversion: 0.4),
        CourtMove(id: "crossover", title: "Crossovers and sharp cuts", video: "video_court_crossover", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: false,
                  why: "A hard plant and cut twists the foot inward under your full body weight. That is the exact load on the ligament that is still healing.",
                  instead: "Rebuild first with slow side slides and figure-of-eights in Sport Lab.",
                  plantar: 0.3, inversion: 0.75),
        CourtMove(id: "contest", title: "Contested jumps and rebounds", video: "video_court_contest", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: true,
                  why: "Most basketball sprains happen landing on another player's foot. The foot rolls in while the toes point down, stretching the ATFL, the ligament you sprained.",
                  instead: "Practise landings on your own first, and wear a brace or tape when you return.",
                  plantar: 0.65, inversion: 1.0,
                  scenes180: [
                    Clip180(label: "The sprain", video: "court180_sprain",
                            line: "Watch her right foot come down on his foot. The ankle rolls in, and the ligament on the outside overstretches.",
                            frames: 0...158),
                    Clip180(label: "Safe landing", video: "court180_safe",
                            line: "Now a safe landing. Both feet, toes forward, knees soft. The ankle stays upright.",
                            frames: 170...290),
                  ]),
        CourtMove(id: "drive", title: "Driving layups and dunks", video: "video_court_drive", verdict: .notYet,
                  opensAt: .returnToActivity, needsJumpClearance: true,
                  why: "Taking off and landing on one foot puts several times your body weight through one ankle.",
                  instead: "Start with the two-foot jump stop drill once your physiotherapist clears jumping.",
                  plantar: 0.55, inversion: 0.6),
    ]

    /// The research behind each move's wording (shown on the Play Smart card; full references in Evidence).
    static let evidenceByMove: [String: [String]] = [
        "shoot": ["okazaki2012", "jospt2021"], "dribble": ["jospt2021"], "defend": ["mcguine2006", "jospt2021"],
        "crossover": ["mckay2001", "jospt2021"], "contest": ["mckay2001", "jospt2021"], "drive": ["paass2021", "mgh"],
        "bm_rally": ["donath2025"], "bm_shuffle": ["fong2023"], "bm_lunge": ["fu2017"], "bm_smash": ["donath2025", "paass2021"],
        "bm_scissor": ["fong2023", "paass2021"],
    ]

    /// What this move means for this person today.
    static func forYou(_ m: CourtMove, profile: PatientProfile?, stage: RehabStage) -> (open: Bool, text: String) {
        if stage < m.opensAt { return (false, "For you: from Stage \(m.opensAt.rawValue), \(m.opensAt.title)") }
        if m.needsJumpClearance, let p = profile, !ClinicalEngine.hopsAllowed(p) {
            return (false, "For you: after your physiotherapist OKs jumping")
        }
        return (true, m.verdict == .care ? "Open for you, with care" : "Open for you now")
    }
}
