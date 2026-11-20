import Foundation
import SwiftUI

// MARK: - Patient profile

enum AnkleSide: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Left ankle" : "Right ankle" }
    var short: String { self == .left ? "Left" : "Right" }
    /// Suffix used by the coach animation clips ("R" / "L").
    var clipSuffix: String { self == .right ? "R" : "L" }
    var opposite: AnkleSide { self == .left ? .right : .left }
}

enum TimeSinceInjury: String, Codable, CaseIterable, Identifiable {
    case under3Days, days3to14, weeks2to6, over6Weeks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .under3Days: return "Less than 3 days"
        case .days3to14: return "3 – 14 days"
        case .weeks2to6: return "2 – 6 weeks"
        case .over6Weeks: return "More than 6 weeks"
        }
    }
    /// Approximate days since injury used to seed the timeline.
    var approxDays: Int {
        switch self {
        case .under3Days: return 1
        case .days3to14: return 7
        case .weeks2to6: return 24
        case .over6Weeks: return 60
        }
    }
}

enum SprainHistory: String, Codable, CaseIterable, Identifiable {
    case first, twoOrThree, many
    var id: String { rawValue }
    var title: String {
        switch self {
        case .first: return "This is my first sprain"
        case .twoOrThree: return "I've sprained it 2–3 times"
        case .many: return "It sprains often"
        }
    }
}

/// The kind of sprain, from how it happened and where it hurts. It changes the plan, the 3D ligament shown and
/// what to avoid. Lateral (inversion) sprains are by far the most common (JOSPT CPG 2021); medial (eversion, deltoid)
/// sprains are rare and often come with other injuries; high ankle (syndesmosis) sprains recover more slowly and
/// need a slower, clinician-guided progression (Williams & Allen 2010).
enum SprainType: String, Codable, CaseIterable, Identifiable {
    case lateral, medial, high, unsure
    var id: String { rawValue }
    /// What the person picks: how it happened, in plain words.
    var title: String {
        switch self {
        case .lateral: return "My foot rolled inward"
        case .medial: return "My foot rolled outward"
        case .high: return "My foot twisted outward"
        case .unsure: return "I'm not sure"
        }
    }
    var detail: String {
        switch self {
        case .lateral: return "Pain on the outside of the ankle"
        case .medial: return "Pain on the inside of the ankle"
        case .high: return "Pain above the ankle, between the shin bones"
        case .unsure: return "We'll start with the safest plan"
        }
    }
    var symbol: String {
        switch self {
        case .lateral: return "arrow.turn.down.left"
        case .medial: return "arrow.turn.down.right"
        case .high: return "arrow.triangle.2.circlepath"
        case .unsure: return "questionmark.circle"
        }
    }
    /// The clinical name, shown on the injury card.
    var name: String {
        switch self {
        case .lateral: return "Outer (lateral) ankle sprain"
        case .medial: return "Inner (medial) ankle sprain"
        case .high: return "High ankle (syndesmosis) sprain"
        case .unsure: return "Ankle sprain, type not confirmed"
        }
    }
    /// Typical recovery, said simply (shown on the injury card; the plan follows the person's progress, not the clock).
    var typicalRecovery: String {
        switch self {
        case .lateral: return "Most people are back to normal activity in 2 to 6 weeks; sport can take longer."
        case .medial: return "Often similar to an outer sprain, but a clinician should rule out other injuries."
        case .high: return "Usually takes longer than an outer sprain, often about twice as long."
        case .unsure: return "A physiotherapist can confirm the type with a quick exam."
        }
    }
}

/// Other old injuries that change what is safe ("don't make it worse").
enum OldInjury: String, Codable, CaseIterable, Identifiable {
    case otherAnkle, fractureOrSurgery, knee, fallLastYear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .otherAnkle: return "I've sprained my other ankle too"
        case .fractureOrSurgery: return "Past fracture or surgery on this ankle"
        case .knee: return "Knee pain or a knee injury"
        case .fallLastYear: return "I've had a fall in the past year"
        }
    }
    var symbol: String {
        switch self {
        case .otherAnkle: return "arrow.left.arrow.right"
        case .fractureOrSurgery: return "bandage"
        case .knee: return "figure.walk"
        case .fallLastYear: return "figure.fall"
        }
    }
}

enum RehabGoal: String, Codable, CaseIterable, Identifiable {
    case dailyLife, walkingHiking, running, courtSports
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dailyLife: return "Everyday walking & stairs"
        case .walkingHiking: return "Long walks & hiking"
        case .running: return "Running"
        case .courtSports: return "Jumping / court & field sports"
        }
    }
    var symbol: String {
        switch self {
        case .dailyLife: return "figure.walk"
        case .walkingHiking: return "figure.hiking"
        case .running: return "figure.run"
        case .courtSports: return "figure.basketball"
        }
    }
}

enum AgeGroup: String, Codable, CaseIterable, Identifiable {
    case under18, adult, over65
    var id: String { rawValue }
    var title: String {
        switch self {
        case .under18: return "Under 18"
        case .adult: return "18 – 64"
        case .over65: return "65 or older"
        }
    }
}

enum WalkAbility: String, Codable, CaseIterable, Identifiable {
    case notYet, withLimp, normally
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notYet: return "Not yet / only a few steps"
        case .withLimp: return "Yes, with a limp"
        case .normally: return "Yes, normally"
        }
    }
}

enum SingleLegAbility: String, Codable, CaseIterable, Identifiable {
    case cannot, withSupport, tenSeconds, thirtySeconds
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cannot: return "I can't / haven't tried"
        case .withSupport: return "Only holding on to something"
        case .tenSeconds: return "About 10 seconds on my own"
        case .thirtySeconds: return "30 seconds or more, steady"
        }
    }
}

enum Swelling: String, Codable, CaseIterable, Identifiable {
    case none, mild, marked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .mild: return "A little"
        case .marked: return "A lot"
        }
    }
}

/// Screening questions adapted from the Ottawa Ankle & Foot Rules and general red flags.
struct RedFlagAnswers: Codable, Equatable {
    var couldNotBearWeight = false      // could not take 4 steps, both straight after the injury and now
    var boneTenderness = false          // tenderness at the back edge/tip of either ankle bone, base of 5th metatarsal or navicular
    var numbnessOrColour = false        // numbness, pins & needles, cold, pale or blue foot
    var deformity = false               // obvious deformity
    var calfPainSwelling = false        // hot, swollen, tender calf (possible DVT)
    var highAnklePain = false           // pain mainly above the ankle / squeezing the shin bones hurts
    var feverOrRedHotJoint = false
}

struct StatusSnapshot: Codable, Equatable {
    var painRest: Int = 2               // 0 – 10
    var walk: WalkAbility = .withLimp
    var singleLeg: SingleLegAbility = .withSupport
    var swelling: Swelling = .mild
}

struct PatientProfile: Codable, Equatable {
    var nickname: String = ""
    var side: AnkleSide = .right
    var timeSince: TimeSinceInjury = .days3to14
    var injuryDate: Date = Date()
    var history: SprainHistory = .first
    var givingWay: Bool = false
    /// Optional so profiles saved before this field existed still decode.
    var oldInjuries: [OldInjury]? = nil
    /// Optional so profiles saved before this field existed still decode.
    var sprainType: SprainType? = nil
    var goal: RehabGoal = .dailyLife
    var playSport: PlaySport? = nil          // the sport or activity Play Smart is tailored to
    var ageGroup: AgeGroup = .adult
    var clinicianGuided: Bool = false
    var hopClearance: Bool = false
    var sessionMinutes: Int = 15
    var reminderHour: Int? = nil
    var redFlags = RedFlagAnswers()
    var baseline = StatusSnapshot()
    var createdAt = Date()

    var daysSinceInjury: Int {
        max(0, Calendar.current.dateComponents([.day], from: injuryDate, to: Date()).day ?? 0)
    }
    /// The sprain type, with older profiles mapped from the "pain above the ankle" safety answer.
    var type: SprainType { sprainType ?? (redFlags.highAnklePain ? .high : .lateral) }
    /// High ankle (syndesmosis) pattern: picked as the type, or pain above the ankle in the safety check.
    var isHighAnkle: Bool { type == .high || redFlags.highAnklePain }
    /// History pattern consistent with chronic ankle instability (CAI).
    var instabilityPattern: Bool { history != .first || givingWay }
    var injuries: Set<OldInjury> {
        get { Set(oldInjuries ?? []) }
        set { oldInjuries = OldInjury.allCases.filter { newValue.contains($0) } }
    }
    /// Higher fall risk: age 65+ or a fall in the past year (World Falls Guidelines 2022).
    var fallRisk: Bool { ageGroup == .over65 || injuries.contains(.fallLastYear) }
}

// MARK: - Stages

enum RehabStage: Int, Codable, CaseIterable, Identifiable, Comparable {
    case protect = 1, load, balance, returnToActivity
    var id: Int { rawValue }
    static func < (a: RehabStage, b: RehabStage) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .protect: return "Protect & Move"
        case .load: return "Load & Restore"
        case .balance: return "Balance & Strength"
        case .returnToActivity: return "Return to Activity"
        }
    }
    var subtitle: String {
        switch self {
        case .protect: return "Calm the ankle and keep it moving gently"
        case .load: return "Walk normally again and rebuild calf and ankle strength"
        case .balance: return "Retrain balance on one leg (proprioception)"
        case .returnToActivity: return "Hops, quick steps and sport-ready control"
        }
    }
    var symbol: String {
        switch self {
        case .protect: return "leaf"
        case .load: return "figure.strengthtraining.functional"
        case .balance: return "figure.mind.and.body"
        case .returnToActivity: return "figure.run"
        }
    }
    var tint: Color {
        switch self {
        case .protect: return Color(red: 0.45, green: 0.78, blue: 0.95)
        case .load: return Color(red: 0.35, green: 0.84, blue: 0.68)
        case .balance: return Color(red: 0.98, green: 0.76, blue: 0.35)
        case .returnToActivity: return Color(red: 0.98, green: 0.52, blue: 0.45)
        }
    }
    var next: RehabStage? { RehabStage(rawValue: rawValue + 1) }
    var previous: RehabStage? { RehabStage(rawValue: rawValue - 1) }
    var goalsText: [String] {
        switch self {
        case .protect:
            return ["Protect the ankle, elevate and compress (PEACE)", "Pain-free ankle movement several times a day", "Start walking as comfort allows"]
        case .load:
            return ["Walk without a limp", "Regain ankle bend (dorsiflexion)", "Strengthen the calf and the muscles around the ankle"]
        case .balance:
            return ["Stand on the injured leg for 30 s, steady", "Control balance while moving arms and head", "Single-leg squats and heel raises"]
        case .returnToActivity:
            return ["Land hops softly and steadily", "Quick steps and direction changes", "Keep training balance 3× a week for 8 weeks"]
        }
    }
    var exitCriteria: String {
        switch self {
        case .protect: return "Pain at rest 3/10 or less and walking without crutches"
        case .load: return "Walking normally and a 20 s single-leg stand without touching down"
        case .balance: return "30 s steady single-leg stand and 25 single-leg heel raises, pain 2/10 or less"
        case .returnToActivity: return "Confident hopping and landing, back to your goal activity"
        }
    }
}

// MARK: - Logs

enum SwellingTrend: String, Codable, CaseIterable, Identifiable {
    case better, same, worse
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DailyCheckIn: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var painRest: Int
    var swelling: SwellingTrend
    var confidence: Int   // 1 – 5
}

struct ExerciseResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var exerciseID: String
    var setsDone: Int = 0
    var setsTarget: Int = 0
    var reps: Int = 0
    var bestHold: Double = 0
    var steadiness: Double? = nil     // 0 – 100 (experimental head-sway score)
    var gameScore: Int? = nil
    var painDuring: Int? = nil
    var skipped = false
}

struct SessionRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var stage: RehabStage
    var results: [ExerciseResult] = []
    var painBefore: Int = 0
    var painAfter: Int? = nil
    var duration: TimeInterval = 0
    var stoppedEarly = false
    var stopReason: String? = nil
}

/// Per-exercise adaptation that follows the person's own response ("habits") over time.
struct ExerciseAdaptation: Codable, Equatable {
    var level: Int = 1          // 1 – 3 (dose / difficulty)
    var painFlags: Int = 0      // times the exercise provoked pain ≥ 4/10
    var easyStreak: Int = 0     // sessions in a row it felt easy and pain-free
    var timesDone: Int = 0
    var timesSkipped: Int = 0
}

struct AppSettings: Codable, Equatable {
    var voiceCoach = true
    var music = true
    var effectsVolume: Double = 0.8
    var musicVolume: Double = 0.55
    var mirrorCoach = true
    var coach: CoachModel = .fitness
    var defaultEnvironment: EnvironmentKind = .goldenMeadow
    var coverage: EnvironmentCoverage = .arc180
    var reduceMotion = false
    /// nil/false: fully immersive 360° session (after the space scan); true: room view (mixed).
    var roomView: Bool? = nil
    var assistantVoice: Bool? = nil
    var healthSync: Bool? = nil
    var spaceChoice: String? = nil         // "ask" (default), "room", "immersive"
    var butterfly: Bool? = nil             // Lumi, the companion butterfly (default on)
    var welcomeDone: Bool? = nil           // first-time welcome tour finished or skipped
    var clinicianName: String? = nil       // the person's physio or doctor (for video calls)
    var clinicianLink: String? = nil       // a Zoom, Teams or FaceTime link, or a phone number
    var pedalSetupDone: Bool? = nil        // went through the iPhone pedal set-up once

    init() {}
    // Tolerant decoding: settings saved by older versions (missing keys) keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        voiceCoach = (try? c.decodeIfPresent(Bool.self, forKey: .voiceCoach)) ?? d.voiceCoach
        music = (try? c.decodeIfPresent(Bool.self, forKey: .music)) ?? d.music
        effectsVolume = (try? c.decodeIfPresent(Double.self, forKey: .effectsVolume)) ?? d.effectsVolume
        musicVolume = (try? c.decodeIfPresent(Double.self, forKey: .musicVolume)) ?? d.musicVolume
        mirrorCoach = (try? c.decodeIfPresent(Bool.self, forKey: .mirrorCoach)) ?? d.mirrorCoach
        coach = (try? c.decodeIfPresent(CoachModel.self, forKey: .coach)) ?? d.coach
        defaultEnvironment = (try? c.decodeIfPresent(EnvironmentKind.self, forKey: .defaultEnvironment)) ?? d.defaultEnvironment
        coverage = (try? c.decodeIfPresent(EnvironmentCoverage.self, forKey: .coverage)) ?? d.coverage
        reduceMotion = (try? c.decodeIfPresent(Bool.self, forKey: .reduceMotion)) ?? d.reduceMotion
        roomView = (try? c.decodeIfPresent(Bool.self, forKey: .roomView)) ?? nil
        assistantVoice = (try? c.decodeIfPresent(Bool.self, forKey: .assistantVoice)) ?? nil
        healthSync = (try? c.decodeIfPresent(Bool.self, forKey: .healthSync)) ?? nil
        spaceChoice = (try? c.decodeIfPresent(String.self, forKey: .spaceChoice)) ?? nil
        butterfly = (try? c.decodeIfPresent(Bool.self, forKey: .butterfly)) ?? nil
        welcomeDone = (try? c.decodeIfPresent(Bool.self, forKey: .welcomeDone)) ?? nil
        clinicianName = (try? c.decodeIfPresent(String.self, forKey: .clinicianName)) ?? nil
        clinicianLink = (try? c.decodeIfPresent(String.self, forKey: .clinicianLink)) ?? nil
        pedalSetupDone = (try? c.decodeIfPresent(Bool.self, forKey: .pedalSetupDone)) ?? nil
    }
}

// MARK: - Environments

enum EnvironmentKind: String, Codable, CaseIterable, Identifiable {
    case dawnLake, riverValley, goldenMeadow, auroraNight
    case physioStudio, recoveryRoom, restorativeGarden
    var id: String { rawValue }
    /// The places offered for training: the indoor spaces (studio, quiet room, garden) when their captures are in the
    /// app, plus the calm nature scenes. Only scenes that really exist are listed, so every choice looks different.
    static var pickerCases: [EnvironmentKind] {
        [.physioStudio, .recoveryRoom, .restorativeGarden].filter(\.isAvailable) + [.goldenMeadow, .dawnLake, .riverValley, .auroraNight]
    }
    /// The scene's 360° capture is bundled with the app.
    var isAvailable: Bool { Bundle.main.url(forResource: imageName, withExtension: "jpg") != nil }
    /// Why the scene is calming, in one line (shown when choosing).
    var calmNote: String {
        switch self {
        case .physioStudio: return "Like a clinic gym, with clear space around you"
        case .recoveryRoom: return "Soft daylight and a quiet room"
        case .restorativeGarden: return "Greenery and birdsong"
        case .goldenMeadow: return "Open nature and a far horizon"
        case .dawnLake: return "Still water and soft morning light"
        case .riverValley: return "The sound of running water"
        case .auroraNight: return "Dim, quiet evening light"
        }
    }
    /// Rooms and gardens built from a projected 360° capture plus real 3D props (see EnvironmentBuilder.space).
    var isSpace: Bool { self == .physioStudio || self == .recoveryRoom || self == .restorativeGarden }
    /// Closest of the original scenes, for game reactions and tints.
    var flavor: SceneFlavor {
        switch self {
        case .physioStudio, .recoveryRoom, .dawnLake: return .dawnLake
        case .restorativeGarden, .goldenMeadow: return .goldenMeadow
        case .riverValley: return .riverValley
        case .auroraNight: return .auroraNight
        }
    }
    var subtitle: String {
        switch self {
        case .physioStudio: return "Bright, open studio"
        case .recoveryRoom: return "Quiet, sunlit room"
        case .restorativeGarden: return "Calm garden terrace"
        case .goldenMeadow: return "Open nature at dusk"
        case .dawnLake: return "Lake at first light"
        case .riverValley: return "Misty river"
        case .auroraNight: return "Lanterns at night"
        }
    }
    var title: String {
        switch self {
        case .physioStudio: return "Movement Studio"
        case .recoveryRoom: return "Recovery Room"
        case .restorativeGarden: return "Restorative Garden"
        case .dawnLake: return "Dawn Lake"
        case .riverValley: return "River Valley"
        case .goldenMeadow: return "Golden Meadow"
        case .auroraNight: return "Lantern Night"
        }
    }
    /// Short voice-over when the scene opens.
    var narration: String {
        switch self {
        case .dawnLake: return "A calm lake at first light. Breathe slowly, and let your shoulders drop."
        case .riverValley: return "A misty river at dawn. Listen to the water, and rest your eyes on the horizon."
        case .goldenMeadow: return "A quiet meadow path at sunset. Every steady moment helps your ankle."
        case .auroraNight: return "A quiet lake under a sky full of stars, with lanterns floating above the water. Every step you take sends another one up."
        case .physioStudio: return "A bright movement studio with plenty of space around you. Stand tall, and breathe out slowly."
        case .recoveryRoom: return "A quiet, sunlit room. Let your shoulders drop, and take your time."
        case .restorativeGarden: return "A calm garden terrace. Listen to the birds, and let your breathing slow down."
        }
    }
    /// Ground colour for the virtual floor in full immersion.
    var groundRGB: (Double, Double, Double) {
        switch self {
        case .dawnLake: return (0.42, 0.40, 0.46)
        case .riverValley: return (0.30, 0.40, 0.26)
        case .goldenMeadow: return (0.55, 0.47, 0.25)
        case .auroraNight: return (0.62, 0.68, 0.78)
        case .physioStudio: return (0.45, 0.33, 0.24)
        case .recoveryRoom: return (0.62, 0.50, 0.38)
        case .restorativeGarden: return (0.52, 0.50, 0.46)
        }
    }
    var imageName: String {
        switch self {
        case .dawnLake: return "env_dawn_lake"
        case .riverValley: return "env_river_valley"
        case .goldenMeadow: return "env_golden_meadow"
        case .auroraNight: return "env_aurora_night"
        case .physioStudio: return "env_studio"
        case .recoveryRoom: return "env_recovery"
        case .restorativeGarden: return "env_garden"
        }
    }
    var ambience: String {
        switch self {
        case .dawnLake: return "amb_lake"
        case .riverValley: return "amb_river"
        case .goldenMeadow: return "amb_meadow"
        case .auroraNight: return "amb_night"
        case .physioStudio: return "amb_studio"
        case .recoveryRoom: return "amb_room"
        case .restorativeGarden: return "amb_garden"
        }
    }
}

/// The four original scene moods that game reactions, tints and sounds are designed around.
enum SceneFlavor { case dawnLake, riverValley, goldenMeadow, auroraNight }

/// How much of the view the virtual environment covers.
enum EnvironmentCoverage: String, Codable, CaseIterable, Identifiable {
    case window60, arc180, full360
    var id: String { rawValue }
    var title: String {
        switch self {
        case .window60: return "60° window"
        case .arc180: return "180° panorama"
        case .full360: return "360° immersive"
        }
    }
    var degrees: Float {
        switch self {
        case .window60: return 60
        case .arc180: return 180
        case .full360: return 360
        }
    }
}

// MARK: - Coach models

enum CoachModel: String, Codable, CaseIterable, Identifiable {
    case fitness, scan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fitness: return "Maya, photoreal coach"
        case .scan: return "Alex, real-person 3D scan"
        }
    }
    var fileName: String { self == .fitness ? "CoachFitness" : "CoachScan" }
    var manifestName: String { self == .fitness ? "coach_fitness_clips" : "coach_scan_clips" }
    var credit: String {
        switch self {
        case .fitness: return "\"Female fitness Model - Ai Generated + Rigged\" by XCoder07 (sketchfab.com/xcoder07), CC BY 4.0. Re-animated, decimated."
        case .scan: return "\"Human 3D model scanned with iPhone X\" by in3D (sketchfab.com/in3D_io), CC BY 4.0. Re-animated."
        }
    }
}
