import SwiftUI

/// Four short screens, one decision each (reduced cognitive load for a first-time headset user):
/// 1. which ankle and when, 2. how it happened (the sprain type), 3. how it is today, 4. a one-tap safety check
/// (Ottawa Ankle Rules and red flags).
/// Everything else (name, history, old injuries, age, goal, session length, reminder) starts with sensible defaults
/// and can be changed later in Settings › My recovery.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var p = PatientProfile()
    @State private var someApply = false
    @State private var olderOrFell = false
    private let total = 4

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 && step <= total {
                HStack(spacing: 8) {
                    ForEach(1...total, id: \.self) { i in
                        Capsule().fill(i <= step ? Theme.accent : Color.white.opacity(0.18)).frame(width: i == step ? 34 : 14, height: 8)
                    }
                    Spacer()
                    Text("\(min(step, total)) of \(total)").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40).padding(.top, 26)
                .animation(.spring, value: step)
            }
            // content sits in the optical centre of the window (no empty glass below short steps); long steps scroll
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch step {
                        case 0: welcome
                        case 1: injury
                        case 2: howItHappened
                        case 3: today
                        case 4: safety
                        default: result
                        }
                    }
                    .padding(40)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height * 0.92, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if step > 0 { navBar }
        }
        .animation(.easeInOut, value: step)
    }

    private var navBar: some View {
        HStack {
            Button("Back") { step -= 1 }.disabled(step == 0)
            Spacer()
            if step < total || (step == total && someApply) {
                Button { step += 1 } label: { Label(step == total ? "See my plan" : "Next", systemImage: "arrow.right") }
                    .buttonStyle(.motialPrimary)
                    .disabled(step == 2 && p.sprainType == nil)
            }
        }
        .padding(.horizontal, 40).padding(.bottom, 28)
    }

    // MARK: Screens
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            HeroCard(art: "art_golden_meadow", symbol: nil, eyebrow: "\(Motial.tagline) · Ankle sprain recovery",
                     title: Motial.name, subtitle: "Four quick questions, then your coach shows you today's plan.",
                     height: 380) {
                Button { step = 1 } label: { Label("Let's begin", systemImage: "arrow.right") }
                    .buttonStyle(.motialPrimary)
            }
            DisclaimerText()
        }
    }

    private var injury: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which ankle, and when?").font(.largeTitle.bold())
            Picker("Ankle", selection: $p.side) {
                ForEach(AnkleSide.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            ChoiceGrid(options: TimeSinceInjury.allCases, selection: $p.timeSince, title: { $0.title }, symbol: { t in ["bolt.heart", "calendar", "calendar.badge.clock", "hourglass"][TimeSinceInjury.allCases.firstIndex(of: t) ?? 0] })
        }
    }

    /// The sprain type, from how it happened: one tap, in plain words (it tailors the plan, the 3D ligament shown
    /// and what to avoid).
    private var howItHappened: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How did it happen?").font(.largeTitle.bold())
            Text("Pick the one that sounds most like it. It tailors your plan.").font(.title3).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(SprainType.allCases) { t in
                    let on = p.type == t && (p.sprainType != nil)
                    Button { p.sprainType = t } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: t.symbol).font(.title2).foregroundStyle(on ? Motial.ink : Motial.pulse)
                                .frame(width: 52, height: 52)
                                .background(on ? Motial.pulse : Motial.pulse.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title).font(.title3.weight(.semibold))
                                Text(t.detail).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .background(on ? Motial.pulse.opacity(0.14) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(on ? Motial.pulse : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.roundedRectangle(radius: 22))
                    .hoverEffect(.lift)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How is it today?").font(.largeTitle.bold())
            Text("Pain at rest: \(p.baseline.painRest)/10").font(.headline)
            PainScale(value: $p.baseline.painRest)
            Text("Can you walk on it?").font(.headline)
            ChoiceGrid(options: WalkAbility.allCases, selection: $p.baseline.walk, title: { $0.title }, symbol: { w in ["figure.roll", "figure.walk.motion", "figure.walk"][WalkAbility.allCases.firstIndex(of: w) ?? 0] }, columns: 3)
            // Only people who already walk normally are asked about one-leg standing (it decides the later stages).
            if p.baseline.walk == .normally {
                Text("Can you stand on the injured leg alone?").font(.headline)
                ChoiceGrid(options: SingleLegAbility.allCases, selection: $p.baseline.singleLeg, title: { $0.title }, symbol: { _ in "figure.stand" }, columns: 4)
            }
        }
    }

    private static let flagLines = [
        "I couldn't take 4 steps after the injury, and still can't",
        "Pressing on the ankle's bony bumps, or the outer edge or inner arch of the foot, is very painful",
        "My foot is numb, tingling, cold, pale or blue",
        "The ankle looks deformed",
        "My calf is hot, swollen and tender",
        "I have a fever, or the joint is red and hot",
        "The pain is mainly above the ankle, between the shin bones",
        "I'm 65 or older, or I've had a fall in the past year",
    ]

    private var safety: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick safety check").font(.largeTitle.bold())
            Text("Does any of this apply to you? (Based on the Ottawa Ankle Rules, which doctors use to decide who needs an X-ray.)")
                .foregroundStyle(.secondary)
            if !someApply {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.flagLines, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel()).font(.title3) }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                HStack(spacing: 14) {
                    Button { clearFlags(); step = total + 1 } label: {
                        Label("None of these", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.motialPrimary)
                    Button { someApply = true } label: { Text("Yes, some apply") }
                        .buttonStyle(.motialSecondary)
                }
            } else {
                Text("Switch on the ones that apply.").font(.headline)
                safetyToggle(Self.flagLines[0], isOn: $p.redFlags.couldNotBearWeight)
                safetyToggle(Self.flagLines[1], isOn: $p.redFlags.boneTenderness)
                safetyToggle(Self.flagLines[2], isOn: $p.redFlags.numbnessOrColour)
                safetyToggle(Self.flagLines[3], isOn: $p.redFlags.deformity)
                safetyToggle(Self.flagLines[4], isOn: $p.redFlags.calfPainSwelling)
                safetyToggle(Self.flagLines[5], isOn: $p.redFlags.feverOrRedHotJoint)
                safetyToggle(Self.flagLines[6], isOn: Binding(get: { p.isHighAnkle }, set: { v in
                    p.redFlags.highAnklePain = v
                    if v && p.type != .medial { p.sprainType = .high }
                }))
                safetyToggle(Self.flagLines[7], isOn: Binding(get: { olderOrFell }, set: { v in
                    olderOrFell = v
                    if v { p.injuries.insert(.fallLastYear) } else { p.injuries.remove(.fallLastYear) }
                }))
            }
        }
    }
    private func clearFlags() {
        p.redFlags = RedFlagAnswers(); olderOrFell = false; p.injuries.remove(.fallLastYear)
    }
    private func safetyToggle(_ text: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(text).font(.title3) }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(isOn.wrappedValue ? Color.red.opacity(0.18) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .tint(.red)
    }

    private var result: some View {
        let triage = ClinicalEngine.triage(p)
        let stage = ClinicalEngine.initialStage(p)
        return VStack(alignment: .leading, spacing: 20) {
            switch triage {
            case .seeClinicianFirst(let reasons):
                Label("Please see a clinician first", systemImage: "cross.case.fill").font(.largeTitle.bold()).foregroundStyle(.red)
                ForEach(reasons, id: \.self) { Text($0).font(.title3) }
                Text("Until then: protect the ankle, elevate it, use compression, and avoid painful walking. You can still explore the 3D ankle and learn about recovery.")
                    .foregroundStyle(.secondary)
            case .cautionNotes(let notes):
                stageSummary(stage)
                Card { ForEach(notes, id: \.self) { Label($0, systemImage: "info.circle").font(.callout) } }
            case .ok:
                stageSummary(stage)
            }
            Button {
                model.completeOnboarding(p)
                dismiss()
            } label: { Text("Start my plan").padding(.horizontal, 24) }
                .buttonStyle(.motialPrimary)
            DisclaimerText()
        }
    }

    private struct BulletLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                configuration.icon.font(.system(size: 7)).foregroundStyle(.secondary)
                configuration.title
            }
        }
    }

    private func stageSummary(_ stage: RehabStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your starting point").font(.title2).foregroundStyle(.secondary)
            StageBadge(stage: stage)
            Text(stage.subtitle).font(.title2)
            StageTrack(current: stage)
            ForEach(stage.goalsText, id: \.self) { Label($0, systemImage: "checkmark.circle") }
            Text(ClinicalEngine.frequencyAdvice(stage, instability: p.instabilityPattern)).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Large, tappable single-choice list.
struct ChoiceList<T: Identifiable & Hashable, L: View>: View {
    let options: [T]
    @Binding var selection: T
    @ViewBuilder var label: (T) -> L
    var body: some View {
        VStack(spacing: 10) {
            ForEach(options) { o in
                Button { selection = o } label: {
                    HStack {
                        label(o).font(.title3)
                        Spacer()
                        Image(systemName: selection == o ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == o ? Color.accentColor : .secondary)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(selection == o ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.roundedRectangle(radius: 20))
                .hoverEffect()
                .accessibilityAddTraits(selection == o ? .isSelected : [])
            }
        }
    }
}
