import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// "Ask Motial": an on-device assistant for questions about the person's plan, the exercises and the ankle.
/// Uses Apple Intelligence (Foundation Models framework, on-device, visionOS 26+) when available, grounded in
/// the person's own plan and Steady's evidence library. Otherwise it answers from a built-in, evidence-based FAQ.
/// It never diagnoses, and it routes red-flag symptoms to a clinician or emergency care.
@MainActor
@Observable
final class SteadyAssistant {
    struct Message: Identifiable, Equatable { let id = UUID(); let fromUser: Bool; let text: String }
    private(set) var messages: [Message] = []
    private(set) var thinking = false
    private(set) var usingAppleIntelligence = false

    #if canImport(FoundationModels)
    @ObservationIgnored private var sessionBox: AnyObject?
    #endif

    func reset() { messages = []; sessionBoxReset() }
    private func sessionBoxReset() {
        #if canImport(FoundationModels)
        sessionBox = nil
        #endif
    }

    static func context(_ model: AppModel) -> String {
        var lines: [String] = []
        if let p = model.profile {
            lines.append("Injured ankle: \(p.side.title). Days since injury: \(p.daysSinceInjury). Sprain history: \(p.history.title). Gives way: \(p.givingWay ? "yes" : "no"). Age group: \(p.ageGroup.title). Goal: \(p.goal.title).")
            if !p.injuries.isEmpty { lines.append("Other old injuries: " + p.injuries.map(\.title).joined(separator: "; ") + ".") }
            lines.append("Hopping cleared by clinician: \(p.hopClearance ? "yes" : "no").")
        }
        lines.append("Current stage: \(model.stage.rawValue) of 4, \(model.stage.title): \(model.stage.subtitle). Next milestone: \(model.stage.exitCriteria).")
        lines.append("Latest pain at rest: \(model.latestPain)/10. Sessions this week: \(model.sessionsThisWeek).")
        lines.append("Today's plan: " + model.todaysPlan.map { "\($0.exercise.title) (\($0.dosage.text))" }.joined(separator: ", ") + ".")
        let terms = model.uploads.flatMap(\.findings).map(\.term)
        if !terms.isEmpty { lines.append("Terms found in the person's uploaded report: " + Set(terms).sorted().joined(separator: ", ") + ".") }
        return lines.joined(separator: "\n")
    }

    static let rules = """
    You are Steady, a friendly ankle-sprain rehabilitation coach inside an Apple Vision Pro app.
    Answer in 2–5 short sentences, warm and encouraging, in plain language.
    Base answers on the JOSPT 2021 ankle sprain guideline, PEACE & LOVE, the Ottawa Ankle Rules and the person's plan below.
    Never diagnose, never interpret images, and never change the plan yourself; suggest asking their physiotherapist.
    If the person mentions severe pain, being unable to take 4 steps, numbness, a cold or blue foot, deformity,
    a hot swollen calf, fever, or a fall with a head injury, tell them to stop and seek medical care (emergency services if severe).
    Pain rule: 0–3/10 is fine, 4–5 ease off, 6+ stop.
    """

    func ask(_ question: String, model: AppModel) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        messages.append(Message(fromUser: true, text: q))
        thinking = true
        defer { thinking = false }
        // Safety first: red flags are answered by rules, never by the model.
        if let urgent = Self.redFlagReply(q) { reply(urgent, model: model); return }
        if let ai = await askAppleIntelligence(q, model: model) { reply(ai, model: model); return }
        reply(Self.faqReply(q, model: model), model: model)
    }

    private func reply(_ text: String, model: AppModel) {
        messages.append(Message(fromUser: false, text: text))
        if model.settings.assistantVoice ?? true { SoundManager.shared.say(text, interrupt: true) }
    }

    private func askAppleIntelligence(_ q: String, model: AppModel) async -> String? {
        #if canImport(FoundationModels)
        if #available(visionOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { usingAppleIntelligence = false; return nil }
            usingAppleIntelligence = true
            let session: LanguageModelSession
            if let s = sessionBox as? LanguageModelSession { session = s } else {
                session = LanguageModelSession(instructions: Self.rules + "\n\nThe person's details:\n" + Self.context(model))
                sessionBox = session
            }
            do {
                let r = try await session.respond(to: q)
                return r.content
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    static func redFlagReply(_ q: String) -> String? {
        let t = q.lowercased()
        let flags = ["numb", "can't walk", "cannot walk", "can't put weight", "cannot bear", "blue", "cold foot", "deform",
                     "calf is swollen", "hot calf", "fever", "hit my head", "unbearable", "severe pain", "pop and", "bone sticking"]
        guard flags.contains(where: { t.contains($0) }) else { return nil }
        return "That needs checking by a clinician before any more exercise. Please stop, rest and elevate the ankle, and contact your doctor today. In Singapore, NurseFirst on 6262 6262 can advise where to go. If it's severe, or you hit your head, call 995 or your local emergency number."
    }

    static func faqReply(_ q: String, model: AppModel) -> String {
        let t = q.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("today", "plan", "what should i do", "exercise") {
            let plan = model.todaysPlan.map { "\($0.exercise.title), \($0.dosage.text)" }.joined(separator: "; ")
            return "Today you're in \(model.stage.title). Your plan is: \(plan). It's matched to your pain today and your sprain history. Take it at your own pace."
        }
        if has("pain", "hurt", "sore") {
            return "Use the traffic light: 0 to 3 out of 10 is fine, 4 to 5 means ease off, and 6 or more means stop. Soreness that settles by the next morning is OK. If it's worse, Motial makes the next session gentler."
        }
        if has("hop", "jump", "run", "sport") {
            return model.profile?.hopClearance == true
                ? "Hopping unlocks in stage 4 once your pain is 0 to 1 and you feel confident. Land softly and stick each landing."
                : "Hopping comes last, after your clinician clears you and your pain is 0 to 1. Until then, the stepping versions build the same control safely."
        }
        if has("ice", "swelling", "swollen") {
            return "Early on, follow PEACE: protect, elevate, avoid anti-inflammatories in the first days, compress, and learn about your injury. Gentle movement, like ankle pumps, also helps move swelling."
        }
        if has("brace", "tape") {
            return "After a sprain, a brace or tape for sport plus balance training lowers the risk of another sprain. Ask your physio which suits you."
        }
        if has("long", "when will", "how many weeks", "recover") {
            return "Most sprains improve over 2 to 6 weeks. Balance training should continue for at least 8 weeks, about 3 times a week, to prevent the next sprain."
        }
        if has("atfl", "ligament", "bone", "xray", "x-ray", "report") {
            return "Open Learn, then the 3D ankle, to see each structure. If you've added your X-ray or report, Motial highlights the parts it mentions and explains them. Your clinician interprets the scan itself."
        }
        return "I can help with your plan, the pain rules, swelling, hopping, braces and how long recovery takes. For anything about your diagnosis, please ask your physiotherapist."
    }
}
