import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importingSong = false
    @State private var analysing = false
    @State private var confirmReset = false
    @State private var showStageOverride = false
    @State private var editProfile = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    HStack {
                        MotialWordmark(size: 26)
                        Spacer()
                        Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                // Debug builds only: quick access for Simulator testing (the Simulator can't scroll this form).
                Section("Test tools (debug builds only)") {
                    HStack(spacing: 12) {
                        Button("Restart onboarding") { model.resetAll() }
                        Button("Welcome tour") { var st = model.settings; st.welcomeDone = false; model.settings = st }
                        Button("Set stage…") { showStageOverride = true }
                    }
                    .buttonStyle(.bordered)
                }
                #endif
                Section {
                    TextField("Name (e.g. Dr Tan, SGH Physiotherapy)", text: Binding(
                        get: { model.settings.clinicianName ?? "" },
                        set: { v in var st = model.settings; st.clinicianName = v.isEmpty ? nil : v; model.settings = st }))
                    TextField("Video call link (Zoom, Teams, FaceTime) or phone number", text: Binding(
                        get: { model.settings.clinicianLink ?? "" },
                        set: { v in var st = model.settings; st.clinicianLink = v.isEmpty ? nil : v; model.settings = st }))
                        .textContentType(.URL)
                    if let url = ClinicianCall.url(model.settings.clinicianLink) {
                        Link(destination: url) { Label("Test the call link", systemImage: "video.fill") }
                    }
                } header: { Text("Your clinician") } footer: {
                    Text("Motial suggests a video call when your answers or progress mean your physio or doctor should take a look. Nothing is shared unless you start the call.")
                }
                Section("Coach & sound") {
                    Toggle("Voice coach", isOn: $model.state.settings.voiceCoach)
                    Toggle("Music & ambience", isOn: $model.state.settings.music)
                    LabeledContent("Music volume") { Slider(value: $model.state.settings.musicVolume, in: 0...1) }
                    LabeledContent("Effects volume") { Slider(value: $model.state.settings.effectsVolume, in: 0...1) }
                    Toggle("Mirror the coach (moves like your reflection)", isOn: $model.state.settings.mirrorCoach)
                    Picker("3D coach", selection: $model.state.settings.coach) {
                        ForEach(CoachModel.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Immersion") {
                    Picker("Where to train", selection: Binding(get: { model.settings.spaceChoice == "room" ? "room" : "immersive" },
                                                                 set: { v in var st = model.settings; st.spaceChoice = v; st.roomView = (v == "room"); model.settings = st })) {
                        Text("Immersive scene (recommended)").tag("immersive")
                        Text("My room").tag("room")
                    }
                    Text("You can switch before every experience, after a quick safety check. Turn the Digital Crown to bring your room back at any time.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(isOn: Binding(get: { model.settings.butterfly ?? true },
                                         set: { v in var st = model.settings; st.butterfly = v; model.settings = st })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lumi, the butterfly guide")
                            Text("Shows where to look and step, breathes with you during rests, and lands on your hand.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Read Ask Motial answers aloud", isOn: Binding(get: { model.settings.assistantVoice ?? true },
                                                                       set: { v in var st = model.settings; st.assistantVoice = v; model.settings = st }))
                }
                Section("Apple Health") {
                    Toggle(isOn: Binding(get: { model.settings.healthSync ?? false },
                                         set: { v in
                                             var st = model.settings; st.healthSync = v; model.settings = st
                                             if v { Task { let ok = await HealthSync.requestAccess(); if !ok { var s2 = model.settings; s2.healthSync = false; model.settings = s2 } } }
                                         })) {
                        VStack(alignment: .leading) {
                            Text("Save sessions to Health as workouts")
                            Text("Motial only writes workouts. It never reads your health data.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!HealthSync.available)
                }
                Section("Environment") {
                    Picker("Default scene", selection: $model.state.settings.defaultEnvironment) {
                        ForEach(EnvironmentKind.pickerCases) { Text($0.title).tag($0) }
                    }
                    Picker("Coverage", selection: $model.state.settings.coverage) {
                        ForEach(EnvironmentCoverage.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Standing exercises always keep your real floor visible (60° or 180°). The 360° scene is used only when you're seated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("My songs for Rhythm Steps") {
                    ForEach(model.state.importedSongs) { s in
                        HStack { Text(s.title); Spacer(); Text("\(Int(s.bpm)) BPM").foregroundStyle(.secondary) }
                            .swipeActions { Button("Delete", role: .destructive) { model.removeSong(s) } }
                    }
                    Button { importingSong = true } label: {
                        Label(analysing ? "Finding the beat…" : "Add a song from Files", systemImage: "music.note.plus")
                    }.disabled(analysing)
                    Text("Songs stay on this device. The tempo is detected automatically.").font(.caption).foregroundStyle(.secondary)
                }
                Section("My recovery") {
                    if let p = model.profile {
                        TextField("Your first name (so your coach can greet you)", text: Binding(
                            get: { model.profile?.nickname ?? "" },
                            set: { v in if var pp = model.profile { pp.nickname = v; model.updateProfile(pp) } }))
                        LabeledContent("Ankle", value: p.side.title)
                        LabeledContent("Stage", value: model.stage.title)
                        Picker("Type of sprain", selection: Binding(
                            get: { model.profile?.type ?? .lateral },
                            set: { v in if var pp = model.profile { pp.sprainType = v; model.updateProfile(pp) } })) {
                            ForEach(SprainType.allCases) { Text($0.name).tag($0) }
                        }
                        Toggle("Clinician has cleared hopping", isOn: Binding(
                            get: { model.profile?.hopClearance ?? false },
                            set: { v in if var pp = model.profile { pp.hopClearance = v; model.updateProfile(pp) } }))
                        Picker("Sprain history", selection: Binding(
                            get: { model.profile?.history ?? .first },
                            set: { v in if var pp = model.profile { pp.history = v; model.updateProfile(pp) } })) {
                            ForEach(SprainHistory.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("My ankle sometimes 'gives way' or feels unstable", isOn: Binding(
                            get: { model.profile?.givingWay ?? false },
                            set: { v in if var pp = model.profile { pp.givingWay = v; model.updateProfile(pp) } }))
                        Picker("Age", selection: Binding(
                            get: { model.profile?.ageGroup ?? .adult },
                            set: { v in if var pp = model.profile { pp.ageGroup = v; model.updateProfile(pp) } })) {
                            ForEach(AgeGroup.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Getting back to", selection: Binding(
                            get: { model.profile?.goal ?? .dailyLife },
                            set: { v in if var pp = model.profile { pp.goal = v; model.updateProfile(pp) } })) {
                            ForEach(RehabGoal.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("A doctor or physiotherapist is guiding my recovery", isOn: Binding(
                            get: { model.profile?.clinicianGuided ?? false },
                            set: { v in if var pp = model.profile { pp.clinicianGuided = v; model.updateProfile(pp) } }))
                        ForEach(OldInjury.allCases) { i in
                            Toggle(isOn: Binding(
                                get: { model.profile?.injuries.contains(i) ?? false },
                                set: { v in if var pp = model.profile { if v { pp.injuries.insert(i) } else { pp.injuries.remove(i) }; model.updateProfile(pp) } })) {
                                Label(i.title, systemImage: i.symbol)
                            }
                        }
                        Picker("Session length", selection: Binding(
                            get: { model.profile?.sessionMinutes ?? 15 },
                            set: { v in if var pp = model.profile { pp.sessionMinutes = v; model.updateProfile(pp) } })) {
                            Text("10 min").tag(10); Text("15 min").tag(15); Text("20 min").tag(20)
                        }
                    }
                    Button("Clinician: set stage manually…") { showStageOverride = true }
                    Button("Answer the setup questions again") { editProfile = true }
                    Button("Show the welcome again (first time in a headset)") {
                        var st = model.settings; st.welcomeDone = false; model.settings = st
                    }
                }
                Section("Privacy") {
                    Text("All data stays on this Apple Vision Pro, encrypted with Data Protection. Motial has no accounts, ads, analytics or tracking. Head and hand positions are processed live to measure balance and are never stored as raw tracking data.")
                        .font(.callout)
                }
                Section("References") { EvidenceList(ids: EvidenceLibrary.all.map(\.id)) }
                Section("Credits") {
                    ForEach(CoachModel.allCases) { Text($0.credit) }
                    Text("3D anatomy and ankle bones: BodyParts3D, © The Database Center for Life Science, licensed under CC BY-SA 2.1 Japan (Mitsuhashi N, et al. Nucleic Acids Res 2009). Modified (decimated, fitted, coloured).")
                    Text("\"Baseball Glove\" by m.lando and \"Baseball\" by Virtua Con, Sketchfab, licensed under CC BY 4.0. Modified (scaled, textures resized, brand markings removed).")
                    Text("\"Stylized Low Poly Rowboat with Paddles\" by Muyaya Concept, Sketchfab, licensed under CC BY 4.0. Modified (scaled, lantern added).")
                    Text("\"3D Cartoon Toy Race Car with Vibrant Colors\" by Skill Artist, Sketchfab, licensed under CC BY 4.0. Modified (re-oriented, scaled).")
                    Text("\"Birch Trees Pack | PS1 Low Poly\" by Vova Truestory, Sketchfab, licensed under CC BY 4.0. Modified (scaled).")
                    Text("\"Cuy3\" convertible by paraje3d and \"Racing Steering Wheel - Game-Ready 3D Model\" by GAMICO, Sketchfab, licensed under CC BY 4.0. Modified (repainted in Motial pearl, original badge, gauge and plate graphics removed, wheel clamp removed).")
                    Text("\"Hot Air Balloon - Low Poly\" by Styro and \"Windmill, Low-Poly\" by FLAREMEDIA, Sketchfab, licensed under CC BY 4.0. Modified (balloons recoloured in the Motial palette).")
                    Text("Dawn sky \"Evening Road 01 (Pure Sky)\" and the \"Leafy Grass\" and \"Asphalt 02\" textures from Poly Haven, CC0.")
                    Text("Lake, river, meadow and night skies, the Dawn Drive sunrise (Bloem Field Sunrise), the Sunset Court sky (Belfast Sunset, Pure Sky) and the track and grass textures (Asphalt Track, Leafy Grass): Poly Haven, CC0. Basketball clips (Sport Lab and Court Smarts): Mixkit Stock Video Free License. Voice: Kokoro-82M (Apache 2.0).")
                    Text("\"Basketball Court\" by Klieg3D, Sketchfab, licensed under CC BY 4.0. Modified (scaled, floor markings redrawn at higher resolution). Used for Sunset Court in Play Smart and Sport Lab.")
                    Text("Exercise motion library, the Sunset Court backdrop, stepping stones, lotus, sound effects and music: original works created for this app.")
                }.font(.caption)
                Section {
                    DisclaimerText()
                    Button("Erase all data", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: model.state.settings) { _, s in model.save(); SoundManager.shared.apply(s) }
            .fileImporter(isPresented: $importingSong, allowedContentTypes: [.audio, .mp3, .mpeg4Audio]) { result in
                guard case .success(let url) = result else { return }
                Task { await importSong(url) }
            }
            .confirmationDialog("Erase all Motial data on this device?", isPresented: $confirmReset) {
                Button("Erase", role: .destructive) { model.resetAll() }
            }
            .sheet(isPresented: $showStageOverride) { StageOverrideSheet() }
            .sheet(isPresented: $editProfile) { OnboardingView().frame(minWidth: 900, minHeight: 700) }
        }
    }

    private func importSong(_ url: URL) async {
        analysing = true; defer { analysing = false }
        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let name = "song_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        let dest = AppModel.documents.appendingPathComponent(name)
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        let result = await Task.detached(priority: .userInitiated) { BeatDetector.analyze(url: dest) }.value
        let title = url.deletingPathExtension().lastPathComponent
        model.addSong(ImportedSong(title: title, fileName: name, bpm: result?.bpm ?? 100, firstBeat: result?.firstBeat ?? 0))
    }
}

struct StageOverrideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var stage: RehabStage = .protect
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set stage (clinician)").font(.title.bold())
            Text("Use this when a physiotherapist or doctor has assessed the ankle and recommends a different stage.").foregroundStyle(.secondary)
            Picker("Stage", selection: $stage) {
                ForEach(RehabStage.allCases) { Text("\($0.rawValue). \($0.title)").tag($0) }
            }.pickerStyle(.inline)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply") { model.setStage(stage); dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 560)
        .onAppear { stage = model.stage }
    }
}
