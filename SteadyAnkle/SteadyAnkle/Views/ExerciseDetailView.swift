import SwiftUI
import RealityKit
import AVKit
import UniformTypeIdentifiers

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let item: ClinicalEngine.PlanItem
    @State private var xray = false
    @State private var mirror = true
    @State private var rig: CoachRig?
    @State private var importing = false
    @State private var player: AVPlayer?
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var activating = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var trying = false
    @State private var tryError: String?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 12) {
                    coachPreview
                    HStack {
                        Toggle(isOn: $xray) { Label("See the ankle", systemImage: "eye") }.toggleStyle(.button)
                        Toggle(isOn: $mirror) { Label("Mirror", systemImage: "arrow.left.and.right") }.toggleStyle(.button)
                    }
                    PhysioDemoCard(exerciseID: item.exercise.id)
                    clinicianVideo
                }
                .frame(width: 420)
                details
            }
            .padding(32)
        }
        .navigationTitle(item.exercise.title)
        .sheet(isPresented: $activating) {
            // the cockpit drive has its own sunrise road, so there's no scene to pick
            let isDrive: Bool = { if case .game(.cockpitDrive) = item.exercise.kind { return true }; return false }()
            ActivationSheet(title: item.exercise.title, needsSupport: !item.exercise.seated,
                            immersivePlace: isDrive ? ("Sunrise road", "exp_dawn_drive") : nil) { room in await tryNow(room: room) }
                .environment(model)
        }
        .onChange(of: xray) { _, v in rig?.setXray(v) }
        .onChange(of: mirror) { _, v in rig?.mirror = v; rig?.refreshSide() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let name = "clinician_\(item.exercise.id).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
            let dest = AppModel.documents.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                model.setClinicianVideo(name, for: item.exercise.id)
                player = AVPlayer(url: dest)
            }
        }
        .onAppear {
            if let u = model.clinicianVideoURL(for: item.exercise.id) { player = AVPlayer(url: u) }
        }
    }

    private var coachPreview: some View {
        RealityView { content in
            let r = CoachRig()
            r.injured = model.profile?.side ?? .right
            r.coach = model.settings.coach
            r.mirror = mirror
            await r.load()
            // fit the life-size coach inside the 420 × 440 pt preview (≈ 0.31 × 0.32 m) so it never covers the buttons below
            r.root.scale = [0.13, 0.13, 0.13]
            r.root.position = [0, -0.14, -0.08]
            r.play(exercise: item.exercise.clip, transition: 0)
            content.add(r.root)
            rig = r
        }
        .frame(width: 420, height: 440)
        .padding(.bottom, 12)
        .accessibilityLabel("3D coach demonstrating \(item.exercise.title)")
    }

    @ViewBuilder private var clinicianVideo: some View {
        Card {
            Label("Your physio's own video", systemImage: "person.crop.rectangle.badge.plus").font(.headline)
            if let player {
                VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                Button {
                    Task { await watchImmersive() }
                } label: { Label("Watch immersive (sit down)", systemImage: "visionpro") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.immersiveOpen)
                Text("180° / 360° videos (Insta360, GoPro MAX, Canon EOS VR) and iPhone spatial videos play life-size around you on visionOS 26.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Ask your physiotherapist to record this exercise in 180° (Insta360, GoPro MAX, Canon EOS VR) or as an iPhone spatial video, then add it here to watch a real person demonstrate it around you.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button { importing = true } label: { Label(player == nil ? "Add video" : "Replace video", systemImage: "plus") }
        }
    }

    /// Starts a one-exercise session with this exercise (same safety check, pain check and STOP as a full session).
    /// Opens a one-exercise session (same pain check and STOP as a full session) after the activation sheet's
    /// place choice and safety check. Returns an error message, or nil once open.
    private func tryNow(room: Bool) async -> String? {
        guard let p = model.profile, !model.immersiveOpen else { return "Another experience is already open." }
        if case .seeClinicianFirst = model.triage { return "Your check-in suggests seeing a clinician first." }
        trying = true; defer { trying = false }
        var st = model.settings; st.roomView = room; model.settings = st
        model.sessionRoomView = room
        try? await Task.sleep(for: .milliseconds(60))
        SoundManager.shared.apply(model.settings)
        let s = SessionController(items: [item], profile: p, stage: model.stage, settings: model.settings,
                                  adaptations: model.state.adaptations, painBefore: model.latestPain)
        s.safetyConfirmed = true
        model.activeSession = s
        switch await openImmersiveSpace(id: "session") {
        case .opened:
            model.immersiveOpen = true; tryError = nil
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
            return nil
        default:
            model.activeSession = nil
            return "Couldn't open the experience. Close other immersive apps and try again."
        }
    }

    private func watchImmersive() async {
        guard let url = model.clinicianVideoURL(for: item.exercise.id) else { return }
        player?.pause()
        model.videoToPlay = url
        if case .opened = await openImmersiveSpace(id: "video") { model.immersiveOpen = true } else { model.videoToPlay = nil }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ActivateExperienceButton(disabled: trying || model.immersiveOpen) { activating = true }
                Text(model.immersiveOpen ? "Finish the session that's running first." : "Just this one, on its own.")
                    .font(.callout).foregroundStyle(.secondary)
                if let e = tryError { Text(e).font(.caption).foregroundStyle(.orange) }
            }
            if item.exercise.kind.isPedalGame && item.exercise.seated {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Motial Pedal on your iPhone", systemImage: "iphone.gen3").font(.title2.bold())
                    Text("Strap your iPhone to the top of your foot with a sports armband, then open Motial Pedal. Your foot becomes the accelerator. No phone? You can still play a demo drive.")
                        .font(.callout).foregroundStyle(.secondary)
                    PhoneLinkCard()
                }
            }
            HStack {
                Text(item.dosage.text).font(.largeTitle.bold().monospacedDigit())
                Text("· rest \(item.dosage.restSeconds) s").foregroundStyle(.secondary)
                Spacer()
                Text("Level \(item.level) of 3").font(.headline).foregroundStyle(.secondary)
            }
            Card {
                MusclesView(exercise: item.exercise) {
                    model.anatomyMode = .muscles(item.exercise.id)
                    openWindow(id: "anatomy")
                }
            }
            Card {
                Text("How to do it").font(.title2.bold())
                ForEach(Array(item.exercise.steps.enumerated()), id: \.offset) { i, s in
                    Label(s, systemImage: "\(i + 1).circle.fill")
                }
            }
            Card {
                Text("Why it helps").font(.title2.bold())
                Text(item.reason)
            }
            if !item.exercise.cautions.isEmpty {
                Card {
                    Label("Safety", systemImage: "shield.lefthalf.filled").font(.title2.bold()).foregroundStyle(.orange)
                    ForEach(item.exercise.cautions, id: \.self) { Text($0) }
                    Text("Stop if pain goes above 5/10 or the ankle feels unstable.")
                }
            }
            Card {
                Text("Evidence").font(.title2.bold())
                EvidenceList(ids: item.exercise.evidence)
            }
        }
    }
}
