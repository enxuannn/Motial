import AppIntents
import Foundation

// Siri and Shortcuts for Motial Pedal.
// On iOS 18+ with Apple Intelligence, Siri understands these App Shortcuts in natural language
// ("Start Motial Pedal", "Set my resting position in Motial Pedal"); they also appear in Spotlight and the Shortcuts app.
// Both open the app, because the motion sensor and the local-network link only run while the app is in the foreground.

struct StartPedalIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Motial Pedal"
    static var description = IntentDescription("Opens Motial Pedal and starts looking for Motial on your Vision Pro.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShinModel.shared.start()
        return .result()
    }
}

struct SetRestingPositionIntent: AppIntent {
    static var title: LocalizedStringResource = "Set resting position"
    static var description = IntentDescription("Relax your foot flat, then run this to set the pedal's resting position.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = ShinModel.shared
        model.start()
        try? await Task.sleep(for: .milliseconds(600))   // let the motion sensor report a first reading
        model.setRest()
        return .result()
    }
}

struct MotialPedalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartPedalIntent(),
                    phrases: ["Start \(.applicationName)", "Open \(.applicationName)", "Connect \(.applicationName)"],
                    shortTitle: "Start pedal",
                    systemImageName: "shoeprints.fill")
        AppShortcut(intent: SetRestingPositionIntent(),
                    phrases: ["Set resting position in \(.applicationName)", "Reset my foot in \(.applicationName)"],
                    shortTitle: "Set resting position",
                    systemImageName: "pause.circle")
    }
}
