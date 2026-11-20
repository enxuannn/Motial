import SwiftUI

@main
struct SteadyApp: App {
    @State private var model = AppModel.shared
    // The immersive scene is the recommended default; the activation sheet sets the style before the space opens.
    @State private var immersionStyle: ImmersionStyle = .progressive(0.35...1.0, initialAmount: 1.0)
    @State private var videoStyle: ImmersionStyle = .full
    @State private var sportStyle: ImmersionStyle = .progressive(0.35...1.0, initialAmount: 1.0)
    @State private var welcomeStyle: ImmersionStyle = .mixed
    @State private var courtStyle: ImmersionStyle = .progressive(0.35...1.0, initialAmount: 1.0)

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .onAppear { model.mainWindowOpen = true }
                .onDisappear { model.mainWindowOpen = false }
                .onChange(of: model.sessionRoomView) { _, room in
                    // chosen in the activation sheet: set the style before the session space opens
                    immersionStyle = room ? .mixed : .progressive(0.35...1.0, initialAmount: 1.0)
                }
                .task {
                    RehabTogether.shared.observe()
                    SoundManager.shared.apply(model.settings)
                    await CoachRig.preload(model.settings.coach)
                }
        }
        .defaultSize(width: 1180, height: 1060)

        WindowGroup(id: "anatomy") {
            AnatomyVolumeView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.7, height: 0.6, depth: 0.6, in: .meters)
        // open beside the main window instead of on top of it
        .defaultWindowPlacement { _, context in
            if let main = context.windows.first(where: { $0.id == "main" }) {
                return WindowPlacement(.trailing(main))
            }
            return WindowPlacement(.utilityPanel)
        }

        // Sessions are fully immersive 360° by default (progressive: the Digital Crown brings the room back);
        // "Room view" in Settings switches to mixed immersion.
        ImmersiveSpace(id: "session") {
            SessionImmersiveView()
                .environment(model)
                .onAppear {
                    immersionStyle = (model.settings.roomView ?? false) ? .mixed : .progressive(0.35...1.0, initialAmount: 1.0)
                }
                .onChange(of: model.sessionRoomView) { _, room in
                    // "Show my room" / "Show scenery" during a session
                    immersionStyle = room ? .mixed : .progressive(0.35...1.0, initialAmount: 1.0)
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .progressive)
        .upperLimbVisibility(.visible)

        // Real-person demonstration videos: 180°/360° (APMP) or spatial video, fully immersive, seated.
        ImmersiveSpace(id: "video") {
            ImmersiveVideoView()
                .environment(model)
        }
        .immersionStyle(selection: $videoStyle, in: .full)

        // Return to Sport: the coach demonstrates sport drills on Sunset Court (progressive: the Digital Crown
        // brings the room back) or in the person's own room (mixed). The person chooses before it opens.
        ImmersiveSpace(id: "sportlab") {
            SportLabImmersiveView()
                .environment(model)
                .onAppear { sportStyle = model.sportRoomView ? .mixed : .progressive(0.35...1.0, initialAmount: 1.0) }
                .onChange(of: model.sportRoomView) { _, room in
                    sportStyle = room ? .mixed : .progressive(0.35...1.0, initialAmount: 1.0)
                }
        }
        .immersionStyle(selection: $sportStyle, in: .mixed, .progressive)
        .upperLimbVisibility(.visible)

        // Court Smarts: real footage on Sunset Court, a 3D ankle that shows why, one card. Fully immersive court
        // (the Digital Crown brings the room back); fixed style so it never switches while opening.
        ImmersiveSpace(id: "courtguide") {
            CourtGuideView()
                .environment(model)
        }
        .immersionStyle(selection: $courtStyle, in: .progressive)

        // First-time welcome: always in the person's own room.
        ImmersiveSpace(id: "welcome") {
            WelcomeImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: $welcomeStyle, in: .mixed)
        .upperLimbVisibility(.visible)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.isOnboarded {
            TabView(selection: $model.tab) {
                TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag("today")
                PlayView().tabItem { Label("Play", systemImage: "figure.basketball") }.tag("play")
                LearnView().tabItem { Label("Learn", systemImage: "book") }.tag("learn")
                ProgressDashboardView().tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag("progress")
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
            }
        } else {
            OnboardingView()
        }
    }
}
