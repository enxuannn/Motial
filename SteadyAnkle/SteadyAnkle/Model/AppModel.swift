import Foundation
import SwiftUI
import UserNotifications

/// Everything the app stores. Kept on-device only (Application Support), never sent anywhere.
struct StoredState: Codable {
    var profile: PatientProfile?
    var stage: RehabStage = .protect
    var checkIns: [DailyCheckIn] = []
    var sessions: [SessionRecord] = []
    var adaptations: [String: ExerciseAdaptation] = [:]
    var settings = AppSettings()
    var importedSongs: [ImportedSong] = []
    var clinicianVideos: [String: String] = [:]     // exerciseID -> file name in Documents
    var stageHistory: [StageChange] = []
    var uploads: [MedicalUpload]? = nil               // the person's own X-rays / reports (educational view only)
}

struct StageChange: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var stage: RehabStage
}

struct ImportedSong: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var fileName: String
    var bpm: Double
    var firstBeat: Double
}

@MainActor
@Observable
final class AppModel {
    var state = StoredState()
    var banner: String?                        // short message after stage changes
    var immersiveOpen = false
    var mainWindowOpen = false
    var showAssistant = false
    var tab = "today"                          // selected tab (Siri can switch it)
    var pendingCall = false                    // set by Siri: open the clinician's video link
    var pendingDrive = false                   // set by Siri / Shortcuts: open Dawn Drive when the app is ready
    var pendingStart = false                   // set by Siri / App Shortcuts: start a session when the app is ready
    var focusUploadID: UUID?                   // upload shown next to the 3D ankle
    enum AnatomyMode: Equatable { case explore, myInjury, muscles(String) }
    var anatomyMode: AnatomyMode = .explore
    var sessionRoomView = false                // live: session shows the real room (mixed) instead of scenery
    var activeSession: SessionController?
    var pendingStageMessage: String?
    var videoToPlay: URL?
    var sportLab: SportLabController?          // Return to Sport (Sport Lab) immersive drill session
    var guideSport: PlaySport = .basketball     // live: which Play Smart guide is open
    var sportRoomView = false                  // live: Sport Lab shows the real room (mixed) instead of the court
    var welcome: WelcomeTour?                  // first-time welcome tour

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("steady_state.json")
    }()

    nonisolated static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static let shared = AppModel()
    init() { load() }

    // MARK: Persistence
    func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(StoredState.self, from: data) { state = s }
        // One-time reset: the person's own room is the default training space (handover rule).
        if !UserDefaults.standard.bool(forKey: "remer.roomDefault") {
            UserDefaults.standard.set(true, forKey: "remer.roomDefault")
            state.settings.roomView = true
            state.settings.spaceChoice = nil
            save()
        }
        // One-time switch for the Motial redesign: the immersive scene is the recommended default (a quick safety
        // check is confirmed before every activation); the person's room stays one tap away.
        if !UserDefaults.standard.bool(forKey: "motial.immersiveDefault") {
            UserDefaults.standard.set(true, forKey: "motial.immersiveDefault")
            state.settings.roomView = false
            state.settings.spaceChoice = "immersive"
            save()
        }
        // One-time move to a scene without water (Golden Meadow); the person can still pick any scene later.
        if !UserDefaults.standard.bool(forKey: "remer.meadowDefault") {
            UserDefaults.standard.set(true, forKey: "remer.meadowDefault")
            state.settings.defaultEnvironment = .goldenMeadow
            save()
        }
        // One-time move to the Movement Studio (a calm, clinic-grade space) when the rehab spaces arrived; older
        // scenes that are no longer offered fall back to it too.
        if !UserDefaults.standard.bool(forKey: "motial.studioDefault") || !EnvironmentKind.pickerCases.contains(state.settings.defaultEnvironment) {
            UserDefaults.standard.set(true, forKey: "motial.studioDefault")
            // the first real scene: the studio when its capture is in the app, otherwise the meadow
            state.settings.defaultEnvironment = EnvironmentKind.pickerCases.first ?? .goldenMeadow
            save()
        }
    }
    func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(state) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
    func resetAll() {
        state = StoredState(); save()
        GameLog.shared.eraseAll()
    }

    // MARK: Derived
    var profile: PatientProfile? { state.profile }
    var isOnboarded: Bool { state.profile != nil }
    var stage: RehabStage { state.stage }
    var settings: AppSettings {
        get { state.settings }
        set { state.settings = newValue; save() }
    }
    var latestPain: Int { state.checkIns.last?.painRest ?? state.profile?.baseline.painRest ?? 0 }
    var checkedInToday: Bool {
        guard let c = state.checkIns.last else { return false }
        return Calendar.current.isDateInToday(c.date)
    }
    var sessionsThisWeek: Int {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return state.sessions.filter { $0.date >= start }.count
    }
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(state.sessions.map { cal.startOfDay(for: $0.date) })
        var d = cal.startOfDay(for: Date()); var n = 0
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }
    var triage: ClinicalEngine.Triage {
        guard let p = state.profile else { return .ok }
        return ClinicalEngine.triage(p)
    }
    var exerciseBlocked: Bool {
        if case .seeClinicianFirst = triage { return true }
        return false
    }
    var todaysPlan: [ClinicalEngine.PlanItem] {
        guard let p = state.profile else { return [] }
        return ClinicalEngine.plan(profile: p, stage: state.stage, adaptations: state.adaptations, latestPain: latestPain,
                                   confidence: state.checkIns.last?.confidence ?? 3)
    }

    // MARK: Actions
    func completeOnboarding(_ p: PatientProfile) {
        var profile = p
        profile.injuryDate = Calendar.current.date(byAdding: .day, value: -p.timeSince.approxDays, to: Date()) ?? Date()
        state.profile = profile
        state.stage = ClinicalEngine.initialStage(profile)
        state.stageHistory = [StageChange(stage: state.stage)]
        state.checkIns.append(DailyCheckIn(painRest: p.baseline.painRest, swelling: .same, confidence: 3))
        save()
        if let h = profile.reminderHour { scheduleReminder(hour: h) }
    }

    func updateProfile(_ p: PatientProfile) {
        state.profile = p
        save()
    }

    func clearRedFlags() {
        guard var p = state.profile else { return }
        p.redFlags = RedFlagAnswers()
        p.clinicianGuided = true
        state.profile = p
        save()
    }

    func addCheckIn(_ c: DailyCheckIn) {
        state.checkIns.append(c)
        reevaluateStage()
        save()
    }

    // MARK: X-rays & reports (educational)
    var uploads: [MedicalUpload] { state.uploads ?? [] }
    var reportCautions: [ReportFinding] { uploads.flatMap(\.findings).filter(\.caution) }
    func addUpload(_ u: MedicalUpload) {
        var list = state.uploads ?? []
        list.insert(u, at: 0)
        state.uploads = list
        save()
    }
    func removeUpload(_ u: MedicalUpload) {
        ReportReader.delete(u)
        state.uploads = (state.uploads ?? []).filter { $0.id != u.id }
        if focusUploadID == u.id { focusUploadID = nil }
        save()
    }

    var badges: Set<Badge> { Badge.earned(state) }

    func record(session: SessionRecord) {
        state.sessions.append(session)
        if settings.healthSync == true { Task { await HealthSync.save(session) } }
        for r in session.results {
            let a = state.adaptations[r.exerciseID] ?? ExerciseAdaptation()
            state.adaptations[r.exerciseID] = ClinicalEngine.adapt(a, result: r)
        }
        reevaluateStage()
        save()
    }

    func setStage(_ s: RehabStage) {
        guard s != state.stage else { return }
        state.stage = s
        state.stageHistory.append(StageChange(stage: s))
        save()
    }

    private func reevaluateStage() {
        guard let p = state.profile else { return }
        let d = ClinicalEngine.evaluate(current: state.stage, profile: p, sessions: state.sessions, checkIns: state.checkIns)
        if d.changed {
            state.stage = d.stage
            state.stageHistory.append(StageChange(stage: d.stage))
            pendingStageMessage = d.message
        }
    }

    // MARK: Media the person adds (songs, clinician spatial videos)
    func addSong(_ s: ImportedSong) { state.importedSongs.append(s); save() }
    func removeSong(_ s: ImportedSong) {
        try? FileManager.default.removeItem(at: Self.documents.appendingPathComponent(s.fileName))
        state.importedSongs.removeAll { $0.id == s.id }; save()
    }
    func setClinicianVideo(_ fileName: String, for exerciseID: String) {
        state.clinicianVideos[exerciseID] = fileName; save()
    }
    func clinicianVideoURL(for exerciseID: String) -> URL? {
        if let name = state.clinicianVideos[exerciseID] {
            let u = Self.documents.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        // demo videos bundled with the app (Resources/Videos): video_<exerciseID>.mov or .mp4
        return Bundle.main.url(forResource: "video_\(exerciseID)", withExtension: "mov")
            ?? Bundle.main.url(forResource: "video_\(exerciseID)", withExtension: "mp4")
    }

    // MARK: Reminders (adherence support)
    func scheduleReminder(hour: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: ["steady.daily"])
            let content = UNMutableNotificationContent()
            content.title = "Time for your ankle session"
            content.body = "A few calm minutes keep your recovery on track."
            var dc = DateComponents(); dc.hour = hour; dc.minute = 0
            let req = UNNotificationRequest(identifier: "steady.daily", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
            center.add(req)
        }
    }
    func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["steady.daily"])
    }
}
