import SwiftUI

/// Play: every game and sport experience in one place, one tab away, never below the fold.
/// 1. Pick your sport (big picture tiles). 2. Play Smart for that sport (learn to move safely, with the coach on court).
/// 3. Sport Lab (relearn the sport's drills with the coach; basketball set shot, layup footwork, jump stop, slides).
/// 4. Dawn Drive (the seated racing game: hands steer, the ankle is the accelerator).
/// Clinical limits stay inside each experience (drills lock with a reason) instead of hiding the experience.
struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var activation: Activation?
    @State private var sportLabOpen = false
    @State private var pedalSetup = false

    enum Activation: String, Identifiable { case drive, playSmart; var id: String { rawValue } }

    private var sport: PlaySport { PlaySport.suggested(for: model.profile) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Motial.Space.xxl) {
                VStack(alignment: .leading, spacing: Motial.Space.s) {
                    Text("PLAY").font(.motialEyebrow).tracking(1.6).foregroundStyle(Motial.pulse)
                    Text("Games and your sport").font(.motialDisplay).lineLimit(1).minimumScaleFactor(0.6)
                }
                sportPicker
                HStack(alignment: .top, spacing: 20) {
                    ExperienceCard(cover: sport.cover, eyebrow: "Learn · Play smart",
                                   title: sport == .everyday ? "Everyday moves" : "Play smart: \(sport.shortTitle)",
                                   subtitle: "See how sprains happen in \(sport == .everyday ? "daily life" : sport.title.lowercased()), and how to move safely.",
                                   height: 300) { activation = .playSmart }
                    ExperienceCard(cover: "exp_sport_lab", eyebrow: "Coach drills · Sunset Court", title: "Sport Lab",
                                   subtitle: "Basketball set shot and footwork, badminton lunge and split step, with your coach.",
                                   height: 300) { sportLabOpen = true }
                }
                ExperienceCard(cover: "exp_dawn_drive", eyebrow: "Seated game · Hands + ankle", title: "Dawn Drive",
                               subtitle: "Steer with your hands, press the accelerator with your ankle, ease off for the gold gates.",
                               locked: driveLock, height: 300) {
                    // first time (and whenever no iPhone is connected yet): connect the pedal step by step first
                    if !ShinLink.shared.connected && model.settings.pedalSetupDone != true { pedalSetup = true } else { activation = .drive }
                }
                Button { pedalSetup = true } label: {
                    Label(ShinLink.shared.connected ? "iPhone pedal connected" : "Set up the iPhone pedal, step by step",
                          systemImage: ShinLink.shared.connected ? "iphone.radiowaves.left.and.right" : "iphone")
                }
                .buttonStyle(.motialSecondary)
                clinicalBasis
            }
            .padding(.horizontal, 40).padding(.vertical, 28)
        }
        .sheet(item: $activation) { a in
            Group {
                switch a {
                case .drive:
                    ActivationSheet(title: "Dawn Drive", immersivePlace: ("Sunrise road", "exp_dawn_drive")) { room in
                        await startDrive(room: room)
                    }
                case .playSmart:
                    ActivationSheet(title: "Play smart", showsPlaceChoice: false) { _ in await openPlaySmart() }
                }
            }
            .environment(model).frame(width: 760)
        }
        .task(id: model.pendingDrive) {
            // started from Siri / Shortcuts ("Start Dawn Drive in Motial")
            guard model.pendingDrive else { return }
            model.pendingDrive = false
            if !ShinLink.shared.connected && model.settings.pedalSetupDone != true { pedalSetup = true } else { activation = .drive }
        }
        .sheet(isPresented: $pedalSetup) {
            PedalSetupFlow { _ in
                pedalSetup = false
                Task { try? await Task.sleep(for: .milliseconds(400)); activation = .drive }
            }
            .environment(model)
        }
        .sheet(isPresented: $sportLabOpen) {
            SportLabView(close: { sportLabOpen = false }).environment(model).frame(minWidth: 980, minHeight: 720)
        }
    }

    // MARK: Clinical basis (progressive disclosure: the evidence behind each experience, with sources)

    @State private var showEvidence = false

    private var clinicalBasis: some View {
        DisclosureGroup(isExpanded: $showEvidence) {
            VStack(alignment: .leading, spacing: Motial.Space.xl) {
                evidenceBlock("Play smart", "Learning how sprains happen and how to land and change direction safely; the most common mechanism is the foot rolling inward under load.", ["mckay2001", "donath2025", "iac2014", "doherty2016"])
                evidenceBlock("Sport Lab", "Sport-specific drills are added only after balance and strength goals are met, with jumps gated by your physiotherapist (return-to-sport consensus).", ["paass2021", "mcguine2006", "okazaki2012", "fu2017", "fong2023", "jospt2021"])
                evidenceBlock("Dawn Drive", "Controlled ankle movement and a slow, smooth release (eccentric control), made engaging as a game to support adherence.", ["jospt2021", "lin2021", "gamesNote"])
                Label("Motial supports, and never replaces, your physiotherapist. Stop if the ankle gives way or pain rises above 5/10.", systemImage: "cross.case")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Motial.Space.l)
        } label: {
            HStack(spacing: Motial.Space.m) {
                Image(systemName: "text.book.closed").font(.title2).foregroundStyle(Motial.pulse)
                    .frame(width: 48, height: 48).background(Motial.pulse.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clinical basis").font(.motialHeadline)
                    Text("Why each experience helps, with the research behind it").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Motial.Space.xl)
        .background(Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
    }

    private func evidenceBlock(_ title: String, _ summary: String, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: Motial.Space.s) {
            Text(title).font(.headline)
            Text(summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            EvidenceList(ids: ids)
        }
    }

    // MARK: Sport picker: five picture tiles, the chosen one outlined

    private var sportPicker: some View {
        VStack(alignment: .leading, spacing: Motial.Space.m) {
            Text("Your sport").font(.motialSection)
            HStack(spacing: Motial.Space.m) {
                ForEach(PlaySport.allCases) { s in
                    let on = s == sport
                    Button { choose(s) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Spacer(minLength: 0)
                            Image(systemName: s.symbol).font(.title2).foregroundStyle(on ? Motial.pulse : .white)
                            Text(s.shortTitle).font(.headline).foregroundStyle(.white)
                        }
                        .padding(Motial.Space.l)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
                        .background { CoverImage(name: s.cover) }
                        .clipShape(RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous)
                            .strokeBorder(on ? Motial.pulse : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.roundedRectangle(radius: Motial.Radius.tile))
                    .hoverEffect(.lift)
                    .accessibilityLabel(s.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var driveLock: String? {
        if model.immersiveOpen { return "Another experience is open" }
        if model.latestPain >= 8 { return "Rest today: pain \(model.latestPain)/10" }
        return nil
    }

    private func choose(_ s: PlaySport) {
        guard var p = model.profile else { return }
        p.playSport = s
        model.updateProfile(p)
    }

    // MARK: Activation

    private func startDrive(room: Bool) async -> String? {
        guard let p = model.profile else { return "Finish setting up first." }
        if case .seeClinicianFirst = model.triage { return "Please see a clinician first." }
        guard !model.immersiveOpen else { return "Another experience is already open." }
        guard let ex = ExerciseLibrary.byID("dawn_drive_cockpit") else { return "Dawn Drive isn't available." }
        let item = ClinicalEngine.PlanItem(exercise: ex, dosage: ex.dosage(level: 1), level: 1, reason: ex.purpose)
        var st = model.settings; st.roomView = room; model.settings = st
        model.sessionRoomView = room
        try? await Task.sleep(for: .milliseconds(60))
        SoundManager.shared.apply(model.settings)
        let s = SessionController(items: [item], profile: p, stage: model.stage, settings: model.settings,
                                  adaptations: model.state.adaptations, painBefore: model.latestPain)
        s.safetyConfirmed = true
        s.directStart = true
        model.activeSession = s
        switch await openImmersiveSpace(id: "session") {
        case .opened:
            model.immersiveOpen = true
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
            return nil
        default:
            model.activeSession = nil
            return "Couldn't open the experience. Close other immersive apps and try again."
        }
    }

    private func openPlaySmart() async -> String? {
        guard !model.immersiveOpen else { return "Another experience is already open." }
        model.guideSport = sport
        switch await openImmersiveSpace(id: "courtguide") {
        case .opened:
            model.immersiveOpen = true
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
            return nil
        default:
            return "Couldn't open. Close other immersive apps and try again."
        }
    }
}
