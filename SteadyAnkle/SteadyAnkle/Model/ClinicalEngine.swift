import Foundation

/// Rule-based clinical logic. Every rule maps to a guideline recommendation (see EvidenceLibrary).
/// This is exercise guidance and education, not diagnosis. Red flags always route the person to a clinician.
enum ClinicalEngine {

    // MARK: Triage

    enum Triage: Equatable {
        case ok
        case seeClinicianFirst([String])     // exercise blocked until a clinician has assessed it
        case cautionNotes([String])          // exercise allowed with extra advice
    }

    static func triage(_ p: PatientProfile) -> Triage {
        var urgent: [String] = []
        let f = p.redFlags
        if f.couldNotBearWeight || f.boneTenderness {
            urgent.append("Your answers match the Ottawa Ankle Rules for a possible fracture. Please get checked (an X-ray may be needed) before starting exercises.")
        }
        if f.numbnessOrColour { urgent.append("Numbness, tingling or a pale, cold or blue foot needs same-day medical review.") }
        if f.deformity { urgent.append("An obvious deformity needs urgent medical care.") }
        if f.calfPainSwelling { urgent.append("A hot, swollen, painful calf can be a blood clot (DVT). Seek medical care today.") }
        if f.feverOrRedHotJoint { urgent.append("Fever or a red, hot joint can mean infection. Seek medical care.") }
        if !urgent.isEmpty { return .seeClinicianFirst(urgent) }

        var notes: [String] = []
        if p.isHighAnkle { notes.append("A high ankle (syndesmosis) sprain recovers more slowly. A physiotherapist should check it, as a scan is sometimes needed; your plan progresses more gently and avoids twisting the foot outward.") }
        if p.type == .medial { notes.append("Inner ankle sprains are less common and can come with other injuries. Please have a clinician check it; your plan avoids pushing the foot outward early on.") }
        if p.type == .unsure { notes.append("Not sure which kind of sprain it is? A physiotherapist can tell with a quick exam. Your plan starts with the most common, safest version.") }
        if p.fallRisk { notes.append("Because \(p.ageGroup == .over65 ? "of your age group" : "you're 65 or older or have had a recent fall"), every standing exercise is done next to a sturdy support, levels stay gentle and hopping is switched off.") }
        if p.injuries.contains(.fractureOrSurgery) { notes.append("This ankle has had a fracture or surgery before. Follow any limits your surgeon or physiotherapist gave you; hopping needs their clearance.") }
        if p.injuries.contains(.knee) { notes.append("Knee-friendly plan: no single-leg squats, and the knee stays soft and over the toes in every standing exercise.") }
        if p.injuries.contains(.otherAnkle) { notes.append("Both ankles have been sprained, so do the balance work on both legs. Balance often drops on both sides after a sprain.") }
        if p.ageGroup == .under18 { notes.append("Please do the programme with a parent, coach or physiotherapist who knows about it.") }
        if p.instabilityPattern { notes.append("Repeated sprains or 'giving way' suggest chronic ankle instability. Balance training is the most important part of your plan, and a physiotherapist review is recommended.") }
        if p.timeSince == .over6Weeks && p.baseline.painRest >= 4 { notes.append("Ongoing pain after 6 weeks should be assessed by a clinician.") }
        return notes.isEmpty ? .ok : .cautionNotes(notes)
    }

    // MARK: Stage

    static func initialStage(_ p: PatientProfile) -> RehabStage {
        let s = p.baseline
        if p.timeSince == .under3Days || s.painRest >= 5 || s.walk == .notYet || s.swelling == .marked { return .protect }
        if s.walk != .normally || s.singleLeg == .cannot || s.singleLeg == .withSupport || s.painRest >= 3 || p.isHighAnkle {
            return .load
        }
        if s.singleLeg == .thirtySeconds && s.painRest <= 1 && (p.timeSince == .weeks2to6 || p.timeSince == .over6Weeks) {
            return .returnToActivity
        }
        return .balance
    }

    /// Hopping requires clinician clearance and is never offered to people 65+.
    static func hopsAllowed(_ p: PatientProfile) -> Bool {
        p.hopClearance && !p.fallRisk && !(p.isHighAnkle && !p.clinicianGuided)
    }

    /// Rhythm Steps variant: weight shifts with feet planted first (progressive weight bearing, Grade A),
    /// then steps, then hops only when hopping is cleared (MGH phase IV).
    static func rhythmMode(stage: RehabStage, profile p: PatientProfile, level: Int) -> RhythmMode {
        switch stage {
        case .protect: return .shift
        case .load: return level <= 1 || p.fallRisk ? .shift : .step
        case .balance: return .step
        case .returnToActivity: return hopsAllowed(p) ? .hop : .step
        }
    }

    // MARK: Plan

    struct PlanItem: Identifiable, Equatable {
        var id: String { exercise.id }
        let exercise: Exercise
        let dosage: Dosage
        let level: Int
        let reason: String
    }

    static func plan(profile p: PatientProfile, stage: RehabStage, adaptations: [String: ExerciseAdaptation], latestPain: Int, confidence: Int = 3) -> [PlanItem] {
        var ids: [String]
        switch stage {
        case .protect:
            ids = ["ankle_pumps", "ankle_alphabet", "lantern_glide_seated"]
            if p.daysSinceInjury >= 3 && latestPain <= 3 { ids.append("seated_eversion") }
        case .load:
            ids = ["ankle_pumps", "lantern_glide_seated", "knee_to_wall", "calf_raise", "lantern_glide", "seated_eversion", "supported_sls", "stepping_stones", "rhythm_steps"]
        case .balance:
            ids = ["single_leg_stance", "sls_reach_catch", "sl_mini_squat", "sls_head_turns", "sl_calf_raise", "lantern_glide", "rhythm_steps", "seated_eversion"]
        case .returnToActivity:
            ids = ["single_leg_stance", "sls_reach_catch", "sl_calf_raise", "rhythm_steps"]
            // Single-leg hopping & agility come last (MGH protocol phase IV; PAASS "hopping, jumping and agility"):
            // only with clinician clearance, pain 0–1/10 in the last 24 h and good ankle confidence.
            if hopsAllowed(p) && latestPain <= 1 && confidence >= 4 {
                ids.insert(contentsOf: ["hop_forward", "side_hop", "river_hops"], at: 1)
            } else {
                ids.append("stepping_stones")   // controlled stepping version until hop criteria are met
            }
        }
        // Pedal games alternate by day for variety: Lantern Glide one day, Dawn Drive the next (same exercise, same dose).
        if (Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0) % 2 == 0 {
            // (the seated slot stays Lantern Glide: the cockpit drive below is already the seated driving game)
            ids = ids.map { $0 == "lantern_glide" ? "dawn_drive" : $0 }
        }
        // The first-person cockpit drive (the racing game) is offered every day while it fits the stage (seated, stages 1–2),
        // straight after the first exercise, so it is always in reach rather than only on alternate days.
        if !ids.contains("dawn_drive_cockpit") { ids.insert("dawn_drive_cockpit", at: min(1, ids.count)) }
        // People with an instability pattern get extra balance volume (Grade A).
        if p.instabilityPattern && stage >= .balance && !ids.contains("sls_head_turns") { ids.append("sls_head_turns") }
        // High ankle sprain: avoid end-range dorsiflexion loading early, and no side steps or hops (they twist the
        // foot outward) until the clinician progresses it (Williams & Allen 2010).
        if p.isHighAnkle && stage <= .load { ids.removeAll { $0 == "knee_to_wall" } }
        if p.isHighAnkle && !p.clinicianGuided { ids.removeAll { ["side_hop", "river_hops"].contains($0) } }
        // Inner (medial) sprain: strengthen the inner ankle (resisted inversion, tibialis posterior) instead of pushing
        // the foot outward while the deltoid ligament heals; outer-ankle work returns from Stage 3.
        if p.type == .medial {
            ids = ids.map { $0 == "seated_eversion" && stage <= .load ? "seated_inversion" : $0 }
            if stage <= .load && !ids.contains("seated_inversion") { ids.append("seated_inversion") }
        }
        // Old knee problems: no single-leg squat (keeps knee load low); heel raises keep the strength work.
        if p.injuries.contains(.knee) { ids.removeAll { $0 == "sl_mini_squat" } }
        // Exercises that repeatedly provoked pain are swapped out for now.
        ids.removeAll { (adaptations[$0]?.painFlags ?? 0) >= 2 && stage > .protect && $0 != "ankle_pumps" }

        // Habits: exercises the person keeps skipping move to the end (still offered, never forced).
        let skippedOften = Set(ids.filter { id in
            let a = adaptations[id] ?? ExerciseAdaptation()
            return a.timesSkipped >= 3 && a.timesSkipped > a.timesDone
        })
        ids = ids.filter { !skippedOften.contains($0) } + ids.filter { skippedOften.contains($0) }

        let maxItems: Int
        switch p.sessionMinutes {
        case ..<11: maxItems = 3
        case ..<16: maxItems = 5
        default: maxItems = 7
        }
        var items: [PlanItem] = []
        for id in ids {
            guard let ex = ExerciseLibrary.byID(id), ex.fits(stage) else { continue }
            if ex.requiresHopClearance && !hopsAllowed(p) { continue }
            let a = adaptations[id] ?? ExerciseAdaptation()
            var level = a.level
            if p.fallRisk { level = min(level, 2) }
            var reason = ex.purpose
            if a.painFlags == 1 { reason = "Kept at an easier level because it was sore last time. " + reason; level = 1 }
            if p.instabilityPattern && ex.measure == .sway { reason = "Extra balance work because of your sprain history. " + reason }
            if p.injuries.contains(.otherAnkle) && ex.singleLeg && ex.measure == .sway { reason = "Do it on both legs. " + reason }
            if p.fallRisk && !ex.seated { reason = "Keep a sturdy support within reach. " + reason }
            if p.isHighAnkle && ex.id == "stepping_stones" { reason = "Straight paths only for your high ankle sprain. " + reason }
            if p.type == .medial && ex.id == "seated_inversion" { reason = "Chosen for your inner ankle sprain. " + reason }
            if skippedOften.contains(id) { reason = "Optional today. " + reason }
            items.append(PlanItem(exercise: ex, dosage: ex.dosage(level: level), level: level, reason: reason))
            if items.count >= maxItems { break }
        }
        return items
    }

    static func frequencyAdvice(_ stage: RehabStage, instability: Bool) -> String {
        switch stage {
        case .protect: return "2–3 short sessions a day. Between sessions: elevate, compress, and walk as comfort allows."
        case .load: return "Once a day. Short walks are part of the treatment."
        case .balance, .returnToActivity:
            return instability ? "3 sessions a week for at least 8 weeks, even after it feels better. Consider a brace for sport."
                               : "3–4 sessions a week. Keep balance training going for 8 weeks to prevent another sprain."
        }
    }

    // MARK: Pain monitoring (traffic light)

    enum PainZone { case green, amber, red }
    /// 0–3 acceptable, 4–5 back off, 6+ stop (adapted from the pain-monitoring model used in tendon & ligament rehab).
    static func zone(_ pain: Int) -> PainZone { pain <= 3 ? .green : (pain <= 5 ? .amber : .red) }

    // MARK: Adaptation (learns from the person's own responses)

    static func adapt(_ a: ExerciseAdaptation, result: ExerciseResult) -> ExerciseAdaptation {
        var n = a
        if result.skipped { n.timesSkipped += 1; return n }
        n.timesDone += 1
        let pain = result.painDuring ?? 0
        if pain >= 4 {
            n.painFlags += 1; n.easyStreak = 0; n.level = max(1, n.level - 1)
        } else {
            let steady = (result.steadiness ?? 80) >= 70
            let complete = result.setsDone >= result.setsTarget
            if pain <= 2 && steady && complete { n.easyStreak += 1 } else { n.easyStreak = 0 }
            if n.easyStreak >= 2 && n.level < 3 { n.level += 1; n.easyStreak = 0 }
            if pain <= 1 && n.painFlags > 0 && n.timesDone % 3 == 0 { n.painFlags -= 1 }
        }
        return n
    }

    // MARK: Progression

    struct StageDecision {
        let stage: RehabStage
        let message: String?
        let changed: Bool
    }

    static func evaluate(current: RehabStage, profile: PatientProfile, sessions: [SessionRecord], checkIns: [DailyCheckIn]) -> StageDecision {
        let recent = sessions.filter { $0.stage == current }.suffix(3)
        let lastCheck = checkIns.last
        // Regression: worse swelling, rising rest pain, or a painful session.
        if let c = lastCheck, (c.swelling == .worse && c.painRest >= 4) || c.painRest >= 6, let prev = current.previous {
            return StageDecision(stage: prev, message: "Your ankle is more irritated today, so we've eased back to \(prev.title). That's normal and it won't slow you down for long.", changed: true)
        }
        if let s = sessions.last, (s.painAfter ?? 0) >= 6, let prev = current.previous {
            return StageDecision(stage: prev, message: "The last session was sore, so the plan is a little gentler today.", changed: true)
        }
        guard let next = current.next, recent.count >= 2 else { return StageDecision(stage: current, message: nil, changed: false) }
        let painOK = recent.allSatisfy { ($0.painAfter ?? 0) <= 2 } && (lastCheck?.painRest ?? 0) <= 2 && lastCheck?.swelling != .worse
        guard painOK else { return StageDecision(stage: current, message: nil, changed: false) }
        let holds = recent.flatMap { $0.results }.filter { ["supported_sls", "single_leg_stance", "sls_head_turns"].contains($0.exerciseID) }
        let bestHold = holds.map(\.bestHold).max() ?? 0
        let bestSteady = holds.compactMap(\.steadiness).max() ?? 0
        // Total single-leg heel raises in one session (reps accumulate across sets).
        let slRaises = recent.flatMap { $0.results }.filter { $0.exerciseID == "sl_calf_raise" }.map(\.reps).max() ?? 0
        let confidence = lastCheck?.confidence ?? 3
        var ready = false
        // Criteria follow the MGH sports PT ankle sprain protocol and the JOSPT 2021 CPG measures.
        switch current {
        case .protect:      // full weight bearing, decreased pain, minimal swelling
            ready = (lastCheck?.painRest ?? 5) <= 3 && lastCheck?.swelling != .worse
        case .load:         // normal gait and single-leg stance of good quality
            ready = bestHold >= 20 && bestSteady >= 55
        case .balance:      // 25 single-leg heel raises, steady 30 s stance, confidence (perception domain of PAASS)
            ready = bestHold >= 30 && bestSteady >= 65 && slRaises >= 25 && confidence >= 3
        case .returnToActivity: ready = false
        }
        if next == .returnToActivity && profile.ageGroup == .over65 { ready = false }
        if ready {
            return StageDecision(stage: next, message: "You've met the goals for \(current.title). Welcome to \(next.title)!", changed: true)
        }
        return StageDecision(stage: current, message: nil, changed: false)
    }

    // MARK: Encouragement (Optimism is part of LOVE)

    static let encouragements = [
        "Every steady second is your ankle relearning balance.",
        "Consistency beats intensity. You showed up today. That's the win.",
        "Your nerves and muscles are building a better ankle with every rep.",
        "Feeling a bit wobbly is exactly how balance improves.",
        "Small steps today, big steps later.",
        "Great control. Your ankle is getting smarter.",
    ]
    static func encouragement(seed: Int = Int(Date().timeIntervalSince1970 / 86400)) -> String {
        encouragements[abs(seed) % encouragements.count]
    }

    /// Encouragement matched to the stage and history: reassurance early, confidence later (LOVE: Optimism; PAASS: athlete perception).
    static func encouragement(stage: RehabStage, profile: PatientProfile?, seed: Int = Int(Date().timeIntervalSince1970 / 86400)) -> String {
        var lines: [String]
        switch stage {
        case .protect:
            lines = ["Gentle movement now helps the ligament heal stronger. You're doing exactly the right thing.",
                     "Swelling and stiffness are normal this week. Each short session helps.",
                     "Rest, raise, move a little. Healing is already under way."]
        case .load:
            lines = ["Walking more each day is part of the treatment, and you're doing it.",
                     "Wobbly is fine. It's how your balance comes back.",
                     "Your calf and ankle are getting stronger with every session."]
        case .balance:
            lines = ["Every steady second is your ankle relearning balance.",
                     "This is the stage that prevents the next sprain. Keep it up.",
                     "Feeling a bit wobbly is exactly how balance improves."]
        case .returnToActivity:
            lines = ["Soft landings, strong ankle. You're nearly back.",
                     "Confidence counts as much as strength, and yours is growing.",
                     "Keep balance training 3× a week, even when it feels fine."]
        }
        if profile?.instabilityPattern == true {
            lines.append("Ankles that have sprained before respond really well to balance training. Every session counts.")
        }
        return lines[abs(seed) % lines.count]
    }
}

// MARK: - Where it hurts & what to avoid (education)

struct InjurySite: Identifiable, Equatable {
    var id: String { structure }
    let structure: String          // AnatomyInfo / ligament key in the 3D ankle
    let title: String
    let why: String
}

struct ActivityAdvice: Identifiable, Equatable {
    var id: String { text }
    let symbol: String
    let text: String
    /// Two to four words for the card; the full sentence shows when the card is tapped.
    var short: String? = nil
    var title: String { short ?? text }
}

extension ClinicalEngine {
    /// Most likely injured structures, from the injury pattern and anything named in the person's report.
    /// Lateral (inversion) sprains injure the ATFL first; bigger sprains add the CFL; pain above the ankle
    /// suggests the syndesmosis (AITFL). JOSPT 2021 CPG; Doherty 2017.
    static func injurySites(_ p: PatientProfile, uploads: [MedicalUpload] = []) -> [InjurySite] {
        var sites: [InjurySite] = []
        if p.isHighAnkle {
            sites.append(InjurySite(structure: "AITFL", title: "High ankle (syndesmosis) ligaments",
                                    why: "They hold the two shin bones together just above the ankle. They heal more slowly."))
        }
        if p.type == .medial {
            sites.append(InjurySite(structure: "Deltoid_TN", title: "Deltoid, the inner ankle ligament",
                                    why: "A strong fan of ligaments on the inside. Rolling the foot outward stretches it."))
        }
        if p.type == .lateral || p.type == .unsure || (p.isHighAnkle && p.type != .medial) {
            sites.append(InjurySite(structure: "ATFL", title: "ATFL, the front outer ankle ligament",
                                    why: p.type == .unsure ? "The most likely one: it's injured in most ankle sprains, when the foot rolls inward."
                                                           : "Rolling the foot inward stretches this ligament first."))
        }
        let bigger = p.baseline.walk == .notYet || p.baseline.painRest >= 6 || p.baseline.swelling == .marked || p.history != .first
        if bigger && p.type != .medial {
            sites.append(InjurySite(structure: "CFL", title: "CFL, the lower outer ankle ligament",
                                    why: "Bigger or repeated sprains often stretch this one too."))
        }
        if p.instabilityPattern {
            sites.append(InjurySite(structure: "fibularis_longus", title: "Fibularis (peroneal) muscles",
                                    why: "After repeated sprains they react more slowly. Balance work retrains them."))
        }
        for f in uploads.flatMap(\.findings) {
            if let s = f.structure, !sites.contains(where: { $0.structure == s }) {
                sites.append(InjurySite(structure: s, title: f.term, why: "Mentioned in your report. " + f.meaning))
            }
        }
        return sites
    }

    /// Activities to avoid for now, and what's fine, by stage (NHS: avoid heat, alcohol and massage for the
    /// first 2–3 days; PEACE: avoid anti-inflammatories early; JOSPT CPG: graded return, brace for sport).
    static func avoid(_ stage: RehabStage, _ p: PatientProfile) -> [ActivityAdvice] {
        var a: [ActivityAdvice] = []
        if p.daysSinceInjury <= 3 {
            a.append(ActivityAdvice(symbol: "flame", text: "Heat, hot baths, alcohol and massage for the first 2–3 days, because they increase swelling", short: "Heat & massage"))
            a.append(ActivityAdvice(symbol: "pills", text: "Anti-inflammatory tablets in the first days, unless your doctor advises them", short: "Anti-inflammatories"))
        }
        switch stage {
        case .protect:
            a.append(ActivityAdvice(symbol: "figure.run", text: "Running, jumping, sport and long walks", short: "Running & sport"))
            a.append(ActivityAdvice(symbol: "mountain.2", text: "Uneven ground, slopes and stepping off kerbs quickly", short: "Uneven ground"))
            a.append(ActivityAdvice(symbol: "shoe", text: "High heels and loose footwear", short: "Heels & loose shoes"))
        case .load:
            a.append(ActivityAdvice(symbol: "figure.run", text: "Running, jumping and sport, for now", short: "Running & sport"))
            a.append(ActivityAdvice(symbol: "mountain.2", text: "Hiking or uneven trails", short: "Trails"))
            a.append(ActivityAdvice(symbol: "shoe", text: "High heels; choose supportive shoes", short: "High heels"))
        case .balance:
            a.append(ActivityAdvice(symbol: "figure.basketball", text: "Cutting, pivoting and jumping sports (basketball, football, badminton)", short: "Cutting & jumping"))
            a.append(ActivityAdvice(symbol: "mountain.2", text: "Trail running and uneven ground at speed", short: "Trail running"))
        case .returnToActivity:
            a.append(ActivityAdvice(symbol: "sportscourt", text: "Full matches before you can hop and land confidently", short: "Full matches"))
            a.append(ActivityAdvice(symbol: "exclamationmark.shield", text: "Playing sport without a brace or tape this season", short: "Sport without a brace"))
        }
        if p.isHighAnkle {
            a.append(ActivityAdvice(symbol: "arrow.turn.up.right", text: "Twisting the foot outwards and deep squats, until your physio clears them", short: "Twisting outward"))
        }
        if p.type == .medial {
            a.append(ActivityAdvice(symbol: "arrow.left.and.right", text: "Wide side steps and pushing the foot outward, for now", short: "Wide side steps"))
        }
        a.append(ActivityAdvice(symbol: "exclamationmark.triangle", text: "Anything that pushes pain above 5/10 or makes it worse the next morning", short: "Pain above 5/10"))
        return a
    }

    static func okToDo(_ stage: RehabStage, _ p: PatientProfile) -> [ActivityAdvice] {
        switch stage {
        case .protect:
            return [ActivityAdvice(symbol: "figure.walk", text: "Short walks as pain allows", short: "Short walks"),
                    ActivityAdvice(symbol: "arrow.up.and.down", text: "Gentle ankle movement several times a day", short: "Gentle movement"),
                    ActivityAdvice(symbol: "bed.double", text: "Elevate and compress the ankle when resting", short: "Elevate & compress")]
        case .load:
            return [ActivityAdvice(symbol: "figure.walk", text: "Walking more each day, on flat ground", short: "Walking more"),
                    ActivityAdvice(symbol: "bicycle", text: "Stationary cycling or swimming", short: "Cycling & swimming"),
                    ActivityAdvice(symbol: "stairs", text: "Stairs, holding the rail", short: "Stairs with a rail")]
        case .balance:
            return [ActivityAdvice(symbol: "figure.walk", text: "Brisk walking and gentle jogging on flat ground if pain-free", short: "Walking & easy jogging"),
                    ActivityAdvice(symbol: "bicycle", text: "Cycling, swimming and the gym (avoiding jumps)", short: "Cycling, swimming, gym")]
        case .returnToActivity:
            return [ActivityAdvice(symbol: "figure.run", text: "Building back up to running and training", short: "Running & training"),
                    ActivityAdvice(symbol: "figure.mind.and.body", text: "Balance training 3× a week for 8 weeks", short: "Balance 3× a week")]
        }
    }

    /// Ottawa rule points: if pressing here is very painful, an X-ray may be needed (Stiell 1993).
    static let ottawaZones: Set<String> = ["fibula", "tibia", "metatarsal_5", "navicular"]
}
