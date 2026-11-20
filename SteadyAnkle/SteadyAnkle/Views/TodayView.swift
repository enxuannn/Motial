import SwiftUI

/// Today: one clear primary action (Activate Experience on today's session), the plan at a glance, the immersive
/// experiences, and everything else one tap away (check-in sheet, recovery details).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL
    @State private var activation: Activation?
    @State private var checkingIn = false
    @State private var showRecovery = false
    @State private var sportLabOpen = false

    enum Activation: String, Identifiable {
        case session, drive, playSmart
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Motial.Space.xxl) {
                    header
                    if let msg = model.pendingStageMessage {
                        HStack(spacing: Motial.Space.l) {
                            Label(msg, systemImage: "sparkles").font(.motialHeadline).foregroundStyle(Motial.gold)
                            Spacer()
                            Button("Got it") { model.pendingStageMessage = nil }.buttonStyle(.motialSecondary)
                        }
                        .padding(Motial.Space.xl)
                        .background(Motial.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
                    }
                    // a video call with the person's own clinician, only when the case calls for it
                    if let r = ClinicianCall.reason(model) { ClinicianCallCard(reason: r) }
                    if case .seeClinicianFirst(let reasons) = model.triage {
                        blockedCard(reasons)
                        FindCareSection()
                    } else {
                        liveFollow
                        // first time in the headset: the short welcome (pinch, coach, Lumi, STOP) comes first
                        if model.settings.welcomeDone != true { WelcomeCard() }
                        if !model.checkedInToday { checkInBanner }
                        sessionHero
                        planStrip
                        recovery
                    }
                }
                .padding(.horizontal, 40).padding(.vertical, 28)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { model.showAssistant = true } label: { Label("Ask \(Motial.name)", systemImage: "sparkles") }
                        .labelStyle(.titleAndIcon)
                    Button {
                        if RehabTogether.shared.isActive { RehabTogether.shared.leave() } else { Task { await RehabTogether.shared.start() } }
                    } label: {
                        Label(RehabTogether.shared.isActive ? "End SharePlay" : "Rehab Together", systemImage: "shareplay")
                    }
                    .labelStyle(.iconOnly)
                    .help("Start SharePlay on a FaceTime call so your physio or a friend can join your session")
                }
            }
            .sheet(item: $activation) { a in
                activationSheet(a).environment(model).frame(width: 760)
            }
            .sheet(isPresented: $checkingIn) {
                CheckInCard { checkingIn = false }.environment(model).frame(width: 760).padding(Motial.Space.l)
            }
            .sheet(isPresented: $sportLabOpen) {
                SportLabView(close: { sportLabOpen = false }).environment(model).frame(minWidth: 980, minHeight: 720)
            }
            .sheet(isPresented: Binding(get: { model.showAssistant }, set: { model.showAssistant = $0 })) {
                AssistantView().environment(model).frame(minWidth: 760, minHeight: 640)
            }
            .task(id: model.pendingCall) {
                guard model.pendingCall else { return }
                model.pendingCall = false
                if let u = ClinicianCall.url(model.settings.clinicianLink) { openURL(u) }
            }
            .task(id: model.pendingStart) {
                // Started from Siri / App Shortcuts: the full in-session safety check runs instead of the sheet
                if model.pendingStart {
                    model.pendingStart = false
                    _ = await startSession(items: model.todaysPlan, room: model.settings.roomView ?? false, confirmed: false)
                }
            }
            .navigationDestination(for: String.self) { id in
                if let item = model.todaysPlan.first(where: { $0.id == id }) { ExerciseDetailView(item: item) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: Motial.Space.xl) {
            VStack(alignment: .leading, spacing: Motial.Space.s) {
                MotialWordmark(size: 22)
                Text(greeting).font(.motialDisplay).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            HStack(spacing: Motial.Space.s) {
                StatusChip(text: "Stage \(model.stage.rawValue) · \(model.stage.title)", symbol: model.stage.symbol)
                if model.streakDays > 0 { StatusChip(text: "\(model.streakDays)", symbol: "flame.fill", tint: Motial.gold) }
                StatusChip(text: "Pain \(model.latestPain)/10", symbol: "waveform.path.ecg", tint: Motial.painColor(model.latestPain))
            }
            .fixedSize()
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
        let n = model.profile?.nickname ?? ""
        return n.isEmpty ? base : "\(base), \(n)"
    }

    // MARK: Check-in (secondary: one row, the questions open in a sheet)

    private var checkInBanner: some View {
        HStack(spacing: Motial.Space.l) {
            Image(systemName: "heart.text.square.fill").font(.title).foregroundStyle(Motial.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("How's your ankle today?").font(.motialHeadline)
                Text("A 10-second check-in tunes today's plan.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check in") { checkingIn = true }.buttonStyle(.motialSecondary)
        }
        .padding(Motial.Space.xl)
        .background(Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
    }

    // MARK: Today's session (the primary action)

    private var sessionHero: some View {
        HeroCard(art: Theme.art(for: model.settings.defaultEnvironment), symbol: nil,
                 eyebrow: "\(model.todaysPlan.count) activities · about \(model.profile?.sessionMinutes ?? 15) min",
                 title: "Today's session",
                 subtitle: model.stage.subtitle,
                 height: 360) {
            VStack(alignment: .leading, spacing: Motial.Space.m) {
                // facts at a glance (Apple Fitness-style metadata row)
                HStack(spacing: Motial.Space.s) {
                    let seated = model.todaysPlan.filter { $0.exercise.seated }.count
                    StatusChip(text: "\(seated) seated · \(model.todaysPlan.count - seated) standing", symbol: "figure.stand")
                    StatusChip(text: "Stops at pain 6/10", symbol: "hand.raised.fill", tint: Motial.caution)
                }
                HStack(spacing: Motial.Space.m) {
                    ActivateExperienceButton(disabled: model.immersiveOpen || model.todaysPlan.isEmpty) { activation = .session }
                    Button { showWhyPlan = true } label: { Label("Why this plan", systemImage: "text.book.closed") }
                        .buttonStyle(.motialSecondary)
                }
            }
        }
        .sheet(isPresented: $showWhyPlan) { whyPlanSheet.environment(model).frame(width: 760, height: 620) }
    }

    @State private var showWhyPlan = false

    /// The clinical reasoning behind today's plan, with sources (progressive disclosure, never in the way).
    private var whyPlanSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Motial.Space.xl) {
                    Text("Stage \(model.stage.rawValue): \(model.stage.title)").font(.motialTitle)
                    Text(model.stage.subtitle).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Label("Next milestone: \(model.stage.exitCriteria)", systemImage: "flag.checkered")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("How the plan is built").font(.motialSection)
                    Text("Exercise therapy with progressive range, strength and balance training is the recommended treatment after an ankle sprain. Balance (proprioceptive) training lowers the risk of another sprain. Each session adapts to your pain: green 0–3 keep going, amber 4–5 easier next time, red 6 or more stop.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    EvidenceList(ids: ["jospt2021", "doherty2017", "hupperets2009", "vuurberg2018", "peacelove"])
                    Label("Motial supports, and never replaces, your doctor or physiotherapist. Singapore emergency: 995. Advice: NurseFirst 6262 6262.", systemImage: "cross.case")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(32)
            }
            .navigationTitle("Why this plan")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showWhyPlan = false } } }
        }
    }

    // MARK: Plan (at a glance; details one tap away)

    private var planStrip: some View {
        VStack(alignment: .leading, spacing: Motial.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your plan").font(.motialSection)
                Spacer()
                Text("Tap an activity for how and why").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Motial.Space.l) {
                    ForEach(Array(model.todaysPlan.enumerated()), id: \.element.id) { i, item in
                        NavigationLink(value: item.id) { ExerciseTile(item: item, index: i + 1).frame(width: 250) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Experiences

    private var sport: PlaySport { PlaySport.suggested(for: model.profile) }

    private var experiences: some View {
        VStack(alignment: .leading, spacing: Motial.Space.m) {
            Text("Experiences").font(.motialSection)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                ExperienceCard(cover: "exp_dawn_drive", eyebrow: "Seated game · Ankle pedal", title: "Dawn Drive",
                               subtitle: "Drive into the sunrise. Pointing your toes is the accelerator.",
                               locked: driveLock) { activation = .drive }
                ExperienceCard(cover: sport.cover, eyebrow: "Learn · Play smart",
                               title: sport == .everyday ? "Everyday moves" : "Back to \(sport.title.lowercased())",
                               subtitle: "See how sprains happen, and how to land and move safely.") {
                    activation = .playSmart
                } extra: {
                    Menu {
                        ForEach(PlaySport.allCases) { s in Button { choose(s) } label: { Label(s.title, systemImage: s.symbol) } }
                    } label: {
                        Label(sport.shortTitle, systemImage: sport.symbol).font(.callout.weight(.semibold))
                    }
                    .accessibilityLabel("Choose a sport")
                }
                if ClinicalEngine.showsSportLab(model.profile, stage: model.stage) {
                    ExperienceCard(cover: "exp_sport_lab", eyebrow: "Return to sport", title: "Sport Lab",
                                   subtitle: "Relearn your sport's moves with your coach on Sunset Court.") { sportLabOpen = true }
                }
            }
        }
    }

    /// The racing game is shown to everyone; it's only held back when today's answers say to rest.
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

    // MARK: Recovery (progressive disclosure)

    private var recovery: some View {
        DisclosureGroup(isExpanded: $showRecovery) {
            VStack(alignment: .leading, spacing: Motial.Space.xl) {
                StageTrack(current: model.stage)
                Label(ClinicalEngine.frequencyAdvice(model.stage, instability: model.profile?.instabilityPattern ?? false), systemImage: "calendar")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                InjuryCard(compact: true)
            }
            .padding(.top, Motial.Space.l)
        } label: {
            HStack(spacing: Motial.Space.m) {
                Image(systemName: "flag.checkered").font(.title2).foregroundStyle(Motial.teal)
                    .frame(width: 48, height: 48).background(Motial.teal.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your recovery").font(.motialHeadline)
                    Text("Next milestone: \(model.stage.exitCriteria)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(Motial.Space.xl)
        .background(Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
    }

    /// When someone shares their session over SharePlay, show it live with cheer buttons (physio view).
    @ViewBuilder private var liveFollow: some View {
        if let r = RehabTogether.shared.remote, model.activeSession == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Live: following a session", systemImage: "shareplay").font(.headline).foregroundStyle(Motial.success)
                HStack(spacing: 22) {
                    StatTile(title: "Exercise", value: r.exercise)
                    StatTile(title: "Now", value: r.phase)
                    StatTile(title: "Reps", value: "\(r.reps)")
                    StatTile(title: "Steadiness", value: "\(r.steadiness)")
                    if let p = r.pain { StatTile(title: "Pain", value: "\(p)/10") }
                }
                HStack {
                    ForEach(["Great control!", "Soft knee!", "Keep breathing", "Nearly there!"], id: \.self) { c in
                        Button(c) { RehabTogether.shared.cheer(c) }.buttonStyle(.motialSecondary)
                    }
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Motial.success.opacity(0.1), in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
        }
    }

    private func blockedCard(_ reasons: [String]) -> some View {
        Card {
            Label("See a clinician before exercising", systemImage: "cross.case.fill").font(.motialTitle).foregroundStyle(Motial.danger)
            ForEach(reasons, id: \.self) { Text($0) }
            Text("Meanwhile: protect, elevate and compress the ankle. You can explore the 3D ankle in Learn.").foregroundStyle(.secondary)
            Button("A clinician has checked my ankle and cleared me to exercise") { model.clearRedFlags() }
                .buttonStyle(.motialSecondary)
        }
    }

    // MARK: Activation

    @ViewBuilder private func activationSheet(_ a: Activation) -> some View {
        switch a {
        case .session:
            ActivationSheet(title: "Today's session", needsSupport: model.todaysPlan.contains { !$0.exercise.seated }) { room in
                await startSession(items: model.todaysPlan, room: room, confirmed: true)
            }
        case .drive:
            ActivationSheet(title: "Dawn Drive", immersivePlace: ("Sunrise road", "exp_dawn_drive")) { room in
                guard let ex = ExerciseLibrary.byID("dawn_drive_cockpit") else { return "Dawn Drive isn't available." }
                let item = ClinicalEngine.PlanItem(exercise: ex, dosage: ex.dosage(level: 1), level: 1, reason: ex.purpose)
                return await startSession(items: [item], room: room, confirmed: true)
            }
        case .playSmart:
            ActivationSheet(title: "Play smart", showsPlaceChoice: false) { _ in await openPlaySmart() }
        }
    }

    /// Opens a session; returns an error message, or nil once the space is open.
    private func startSession(items: [ClinicalEngine.PlanItem], room: Bool, confirmed: Bool) async -> String? {
        guard let p = model.profile else { return "Finish setting up first." }
        if case .seeClinicianFirst = model.triage { return "Please see a clinician first." }
        guard !model.immersiveOpen else { return "Another experience is already open." }
        var st = model.settings; st.roomView = room; model.settings = st
        model.sessionRoomView = room                     // sets the immersion style before the space opens
        try? await Task.sleep(for: .milliseconds(60))
        SoundManager.shared.apply(model.settings)
        let s = SessionController(items: items, profile: p, stage: model.stage, settings: model.settings,
                                  adaptations: model.state.adaptations, painBefore: model.latestPain)
        s.safetyConfirmed = confirmed
        model.activeSession = s
        switch await openImmersiveSpace(id: "session") {
        case .opened:
            model.immersiveOpen = true
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")          // the window would otherwise overlap the coach
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

struct CheckInCard: View {
    @Environment(AppModel.self) private var model
    var onDone: (() -> Void)? = nil
    @State private var pain = 2
    @State private var swelling: SwellingTrend = .same
    @State private var confidence = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY CHECK-IN").font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.gold)
                Text("How's your ankle today?").font(.motialTitle)
                Text("10 seconds. Today's plan adapts to your answers.").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Pain at rest: \(pain)/10").font(.headline)
                PainScale(value: $pain)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Swelling vs yesterday").font(.headline)
                    Picker("Swelling", selection: $swelling) {
                        ForEach(SwellingTrend.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("How confident is your ankle?").font(.headline)
                    Picker("Confidence", selection: $confidence) {
                        ForEach(1...5, id: \.self) { Text(["Shaky", "Unsure", "Okay", "Good", "Strong"][$0 - 1]).tag($0) }
                    }.pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button {
                    model.addCheckIn(DailyCheckIn(painRest: pain, swelling: swelling, confidence: confidence))
                    onDone?()
                } label: { Label("Save check-in", systemImage: "checkmark") }
                    .buttonStyle(.motialPrimary)
            }
        }
        .padding(24)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear { pain = model.latestPain }
    }
}
