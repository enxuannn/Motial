import AppIntents
import Foundation

/// Siri & Shortcuts. "Hey Siri, start my ankle session in Motial", "Log ankle pain in Motial",
/// "What's my ankle plan in Motial".
struct StartSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start ankle session"
    static var description = IntentDescription("Opens Motial and starts today's guided rehab session.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.isOnboarded else { return .result(dialog: "Open Motial first to set up your plan.") }
        if case .seeClinicianFirst = model.triage {
            return .result(dialog: "Your answers suggest seeing a clinician before exercising. Open Motial for details.")
        }
        model.pendingStart = true
        return .result(dialog: "Starting \(model.stage.title). Find a clear, safe space and I'll scan the room with you.")
    }
}

struct LogPainIntent: AppIntent {
    static var title: LocalizedStringResource = "Log ankle pain"
    static var description = IntentDescription("Records today's ankle pain at rest (0–10) so the plan adapts.")

    @Parameter(title: "Pain (0–10)", inclusiveRange: (0, 10))
    var pain: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.addCheckIn(DailyCheckIn(painRest: pain, swelling: .same, confidence: model.state.checkIns.last?.confidence ?? 3))
        let advice: String
        switch ClinicalEngine.zone(pain) {
        case .green: advice = "That's in the green zone. Today's plan stays on track."
        case .amber: advice = "That's amber, so today's plan will be gentler."
        case .red: advice = "That's high. Rest and elevate the ankle today, and contact a clinician if it doesn't settle."
        }
        return .result(dialog: "Logged pain \(pain) out of 10. \(advice)")
    }
}

struct TodayPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's ankle plan"
    static var description = IntentDescription("Tells you today's exercises and your current stage.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.isOnboarded else { return .result(dialog: "Open Motial first to set up your plan.") }
        let plan = model.todaysPlan.map(\.exercise.title).joined(separator: ", ")
        return .result(dialog: "You're in stage \(model.stage.rawValue), \(model.stage.title). Today: \(plan).")
    }
}

/// "Start Dawn Drive in Motial": opens Play and the drive (with the iPhone pedal set-up the first time).
struct StartDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Dawn Drive"
    static var description = IntentDescription("Opens Motial's seated driving game. Your iPhone, on your foot, is the pedal.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.isOnboarded else { return .result(dialog: "Open Motial first to set up your plan.") }
        if case .seeClinicianFirst = model.triage {
            return .result(dialog: "Your answers suggest seeing a clinician before exercising. Open Motial for details.")
        }
        model.tab = "play"
        model.pendingDrive = true
        return .result(dialog: "Opening Dawn Drive. Sit on a sturdy chair with your back supported.")
    }
}

/// "Call my physio in Motial": opens the video link the person saved (Zoom, Teams, FaceTime or a number).
struct CallClinicianIntent: AppIntent {
    static var title: LocalizedStringResource = "Video call my clinician"
    static var description = IntentDescription("Starts a video call with your physiotherapist or doctor, using the link saved in Motial.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard ClinicianCall.url(model.settings.clinicianLink) != nil else {
            model.tab = "settings"
            return .result(dialog: "Add your clinician's video link in Motial's Settings first. For advice now, call NurseFirst on 6262 6262.")
        }
        model.tab = "today"
        model.pendingCall = true
        return .result(dialog: "Calling \(model.settings.clinicianName ?? "your clinician").")
    }
}

/// "What's my ankle injury in Motial": the sprain type, the stage and today's main thing to avoid.
struct MyInjuryIntent: AppIntent {
    static var title: LocalizedStringResource = "About my ankle injury"
    static var description = IntentDescription("Tells you your type of sprain, your stage, and what to avoid for now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let p = model.profile else { return .result(dialog: "Open Motial first to set up your plan.") }
        let avoid = ClinicalEngine.avoid(model.stage, p).first?.text.lowercased() ?? "anything that pushes pain above 5 out of 10"
        return .result(dialog: "You have \(p.type.name.lowercased()). You're in stage \(model.stage.rawValue), \(model.stage.title). For now, avoid \(avoid).")
    }
}

struct SteadyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSessionIntent(),
                    phrases: ["Start my ankle session in \(.applicationName)", "Start rehab in \(.applicationName)"],
                    shortTitle: "Start session", systemImageName: "figure.mind.and.body")
        AppShortcut(intent: LogPainIntent(),
                    phrases: ["Log ankle pain in \(.applicationName)", "Record my ankle pain in \(.applicationName)"],
                    shortTitle: "Log pain", systemImageName: "waveform.path.ecg")
        AppShortcut(intent: StartDriveIntent(),
                    phrases: ["Start Dawn Drive in \(.applicationName)", "Start my drive in \(.applicationName)"],
                    shortTitle: "Dawn Drive", systemImageName: "steeringwheel")
        AppShortcut(intent: CallClinicianIntent(),
                    phrases: ["Call my physio in \(.applicationName)", "Video call my clinician in \(.applicationName)"],
                    shortTitle: "Call my physio", systemImageName: "video.fill")
        AppShortcut(intent: MyInjuryIntent(),
                    phrases: ["What's my ankle injury in \(.applicationName)", "About my sprain in \(.applicationName)"],
                    shortTitle: "My injury", systemImageName: "cross.case")
        AppShortcut(intent: TodayPlanIntent(),
                    phrases: ["What's my ankle plan in \(.applicationName)", "Today's plan in \(.applicationName)"],
                    shortTitle: "Today's plan", systemImageName: "list.bullet.clipboard")
    }
}
