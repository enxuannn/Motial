import Foundation
import GroupActivities

/// SharePlay "Rehab Together": during a FaceTime call, a physiotherapist (or a friend) joins the session.
/// On Vision Pro each person appears as a spatial Persona; Steady keeps everyone on the same exercise and shows
/// the person's live reps, hold time and pain check, so a clinician can coach remotely.
struct RehabTogetherActivity: GroupActivity {
    static let activityIdentifier = "sg.edu.nus.did.SteadyAnkle.rehab-together"
    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = "Rehab Together"
        m.subtitle = "Ankle rehab session with Motial"
        m.type = .workoutTogether
        return m
    }
}

/// What the person doing the session shares (no health records: just what the coach needs live).
struct LiveSessionState: Codable, Equatable {
    var exercise: String
    var phase: String
    var reps: Int
    var secondsLeft: Int
    var pain: Int?
    var steadiness: Int
}

@MainActor
@Observable
final class RehabTogether {
    static let shared = RehabTogether()

    private(set) var isActive = false
    private(set) var participants = 0
    private(set) var remote: LiveSessionState?        // what the other person is doing
    private(set) var lastCheer: String?

    @ObservationIgnored private var session: GroupSession<RehabTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// Starts SharePlay (needs an active FaceTime call; otherwise the system offers to start one).
    func start() async {
        let activity = RehabTogetherActivity()
        switch await activity.prepareForActivation() {
        case .activationPreferred: _ = try? await activity.activate()
        default: break
        }
    }

    /// Listen for sessions (call once at app launch).
    func observe() {
        tasks.append(Task { @MainActor in
            for await s in RehabTogetherActivity.sessions() { self.join(s) }
        })
    }

    private func join(_ s: GroupSession<RehabTogetherActivity>) {
        session = s
        let m = GroupSessionMessenger(session: s)
        messenger = m
        // Spatial Personas share the same immersive space as the person and the coach.
        tasks.append(Task { @MainActor in
            if let coordinator = await s.systemCoordinator {
                var cfg = SystemCoordinator.Configuration()
                cfg.supportsGroupImmersiveSpace = true
                coordinator.configuration = cfg
            }
        })
        tasks.append(Task { @MainActor in
            for await (state, _) in m.messages(of: LiveSessionState.self) { self.remote = state }
        })
        tasks.append(Task { @MainActor in
            for await (cheer, _) in m.messages(of: String.self) {
                self.lastCheer = cheer
                SoundManager.shared.play("sfx_success", volume: 0.5)
                SoundManager.shared.say(cheer)
            }
        })
        tasks.append(Task { @MainActor in
            for await st in s.$state.values {
                if case .invalidated = st { self.leave() }
            }
        })
        tasks.append(Task { @MainActor in
            for await p in s.$activeParticipants.values { self.participants = p.count }
        })
        s.join()
        isActive = true
    }

    func leave() {
        session?.leave()
        session = nil; messenger = nil
        isActive = false; remote = nil; participants = 0
    }

    func broadcast(_ state: LiveSessionState) {
        guard let messenger, isActive else { return }
        Task { try? await messenger.send(state) }
    }

    /// The physio or friend sends encouragement that the coach speaks aloud.
    func cheer(_ text: String) {
        guard let messenger, isActive else { return }
        Task { try? await messenger.send(text) }
    }
}
