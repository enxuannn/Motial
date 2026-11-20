import SwiftUI

struct LearnView: View {
    @Environment(\.openWindow) private var openWindow

    private struct Topic: Identifiable {
        let id: String; let title: String; let symbol: String; let body: [String]; let evidence: [String]
    }
    private let topics: [Topic] = [
        Topic(id: "what", title: "What happened to my ankle?", symbol: "questionmark.circle",
              body: ["Most sprains happen when the foot rolls inward (inversion) while pointing down.",
                     "This stretches or tears the outer ligaments: first the ATFL, and in bigger sprains also the CFL.",
                     "Ligaments heal over weeks, but balance (proprioception) and strength need training to come back."],
              evidence: ["jospt2021"]),
        Topic(id: "peace", title: "PEACE & LOVE", symbol: "heart.text.square",
              body: ["First days: Protect · Elevate · Avoid anti-inflammatories early (they may slow healing) · Compress · Educate.",
                     "Then: Load (move and walk as pain allows) · Optimism · Vascularisation (gentle cardio) · Exercise."],
              evidence: ["peacelove", "vuurberg2018"]),
        Topic(id: "balance", title: "Why balance training matters", symbol: "figure.mind.and.body",
              body: ["Around 4 in 10 people develop ongoing ankle instability after a first sprain.",
                     "An 8-week home balance programme cut re-sprains by about a third, but most people didn't finish it.",
                     "Motial turns that programme into short, guided sessions you'll actually want to do."],
              evidence: ["doherty2016", "hupperets2009", "doherty2017"]),
        Topic(id: "doctor", title: "When to see a doctor", symbol: "cross.case",
              body: ["You couldn't take 4 steps straight after the injury and still can't.",
                     "Pressing on the back edge or tip of either ankle bone, the base of the 5th metatarsal or the navicular is very painful (Ottawa Ankle Rules).",
                     "Numbness, a cold or blue foot, deformity, a hot swollen calf, fever, or no improvement after 1–2 weeks."],
              evidence: ["ottawa"]),
        Topic(id: "pain", title: "Pain rules while training", symbol: "gauge.with.dots.needle.33percent",
              body: ["0–3 / 10 (green): fine, keep going.", "4–5 / 10 (amber): ease off; the plan will adjust.",
                     "6+ / 10 (red): stop, rest the ankle, and check in with a clinician if it persists.",
                     "Soreness that settles by the next morning is OK. If it's worse, the next session automatically gets gentler."],
              evidence: ["jospt2021"]),
        Topic(id: "sport", title: "Back to sport", symbol: "figure.run",
              body: ["Return when you can hop and land steadily without pain and feel confident.",
                     "After a sprain, wearing a brace or tape for sport plus balance training lowers the risk of re-injury (Grade A).",
                     "Keep balance training 3× a week for at least 8 weeks."],
              evidence: ["jospt2021", "doherty2017"]),
        Topic(id: "privacy", title: "How Motial measures you", symbol: "lock.shield",
              body: ["Balance, reps and hops are worked out from the headset's head position, and catching uses hand tracking if you allow it.",
                     "No camera images are used. Everything stays on this Vision Pro unless you choose to share a report.",
                     "The steadiness score is a training aid, not a medical test."],
              evidence: ["sylcott2021"]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button { openWindow(id: "anatomy") } label: {
                        HeroCard(art: "art_aurora_night", figure: "art_anatomy", eyebrow: "Interactive 3D · real CT anatomy",
                                 title: "Explore your ankle", subtitle: "Tap any bone, muscle or ligament, and watch how a sprain stretches the ATFL.", height: 320) {
                            Label("Open 3D ankle", systemImage: "cube.transparent").font(.headline)
                                .padding(.horizontal, 16).padding(.vertical, 8).background(Theme.accent, in: Capsule()).foregroundStyle(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    InjuryCard()
                    MyScansSection()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)], spacing: 22) {
                        ForEach(topics) { t in
                            Card {
                                HStack(spacing: 14) {
                                    Image(systemName: t.symbol).font(.title2).foregroundStyle(Theme.accent)
                                        .frame(width: 52, height: 52).background(Theme.accent.opacity(0.15), in: Circle())
                                    Text(t.title).font(.title2.bold())
                                }
                                ForEach(t.body, id: \.self) { Text($0) }
                                DisclosureGroup("Evidence") { EvidenceList(ids: t.evidence) }.font(.callout)
                            }
                        }
                    }
                    FindCareSection()
                    DisclaimerText()
                }
                .padding(32)
            }
            .navigationTitle("Learn")
        }
    }
}
