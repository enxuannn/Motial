import SwiftUI

/// Connecting the Motial Pedal iPhone app, one step per screen: one picture, one short sentence, one button.
/// The connection step watches the live link and moves on by itself; the range step waits until the person has
/// pointed their toes down once, so they've felt the pedal work before the drive starts.
struct PedalSetupFlow: View {
    @Environment(AppModel.self) private var model
    /// Finished all steps (true) or chose to drive without the iPhone (false).
    var onFinish: (_ withPhone: Bool) -> Void
    var finishTitle = "Start Dawn Drive"

    enum Step: Int, CaseIterable { case intro, app, wifi, connect, strap, range, ready }
    @State private var step: Step = .intro
    @State private var triedPedal = false
    @State private var showHelp = false
    private var link: ShinLink { ShinLink.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Motial.Space.xl) {
            // progress
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Motial.pulse : Color.white.opacity(0.16))
                        .frame(width: s == step ? 28 : 10, height: 6)
                }
                Spacer()
                Text("IPHONE PEDAL").font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.pulse)
            }
            .animation(.smooth, value: step)

            content
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)

            HStack {
                if step != .intro && step != .ready {
                    Button("Back") { go(Step(rawValue: step.rawValue - 1) ?? .intro) }.buttonStyle(.motialSecondary)
                }
                Spacer()
                primary
            }
        }
        .padding(Motial.Space.xxl)
        .frame(width: 640)
        .animation(.smooth(duration: 0.3), value: step)
        .onAppear { ShinLink.shared.start(); say(step) }
        .onChange(of: link.connected) { _, c in if c && step == .connect { step = .strap; say(.strap, prefix: "iPhone connected.") } }
        .onChange(of: link.value) { _, v in if v > 0.6 { triedPedal = true } }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            page("shoeprints.fill", "Your foot is the accelerator",
                 "Your iPhone, strapped to your foot, becomes the pedal. Setting it up takes about a minute.")
        case .app:
            page("iphone", "Open Motial Pedal on your iPhone",
                 "Don't have it yet? Ask your physio or clinic for the install link.")
        case .wifi:
            VStack(alignment: .leading, spacing: Motial.Space.l) {
                HStack(spacing: 18) {
                    Image(systemName: "iphone").font(.system(size: 44))
                    Image(systemName: "wifi").font(.system(size: 30)).foregroundStyle(Motial.pulse).symbolEffect(.variableColor.iterative)
                    Image(systemName: "visionpro").font(.system(size: 44))
                }
                .padding(.bottom, 6)
                Text("Join the same Wi-Fi").font(.motialTitle)
                Text("Your iPhone and Vision Pro talk to each other directly. Nothing goes online.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .connect:
            VStack(alignment: .leading, spacing: Motial.Space.l) {
                ZStack {
                    Circle().fill(link.connected ? Motial.pulse.opacity(0.25) : Color.white.opacity(0.08)).frame(width: 88, height: 88)
                    Image(systemName: link.connected ? "checkmark" : "iphone.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(link.connected ? Motial.pulse : .white)
                        .symbolEffect(.pulse, isActive: !link.connected)
                }
                Text(link.connected ? "Connected to \(link.phoneName ?? "your iPhone")" : "Looking for your iPhone…").font(.motialTitle)
                Text("If asked about Local Network, tap Allow on both devices.")
                    .font(.title3).foregroundStyle(.secondary)
                if showHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Keep Motial Pedal open on the iPhone screen.", systemImage: "iphone")
                        Label("Office or school Wi-Fi can block devices. Try your phone's hotspot.", systemImage: "personalhotspot")
                        Label("Check Settings › Privacy › Local Network on the iPhone.", systemImage: "lock.shield")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Not connecting?") { showHelp = true }.buttonStyle(.borderless).font(.callout)
                }
            }
        case .strap:
            page("chair.fill", "Strap it to your foot",
                 "Use a sports armband on top of your foot, screen up. Sit on a sturdy chair with your back supported.")
        case .range:
            VStack(alignment: .leading, spacing: Motial.Space.l) {
                Image(systemName: "arrow.down.circle").font(.system(size: 52)).foregroundStyle(Motial.pulse)
                Text("Set your range on the iPhone").font(.motialTitle)
                Text("Foot flat: tap Set resting position. Then point your toes down: tap Set full range.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(triedPedal ? "Great, the pedal works." : "Now try it: point your toes down slowly.")
                        .font(.headline).foregroundStyle(triedPedal ? Motial.pulse : .white)
                    PedalBar(level: Double(link.value))
                }
            }
        case .ready:
            page("checkmark.circle.fill", "You're ready to drive",
                 "Toes down to speed up. Bring them up slowly before each gold gate.")
        }
    }

    @ViewBuilder private var primary: some View {
        switch step {
        case .intro:
            HStack(spacing: Motial.Space.m) {
                Button("Drive without it") { finish(false) }.buttonStyle(.motialSecondary)
                Button { go(.app) } label: { Label("Set up my iPhone", systemImage: "arrow.right") }.buttonStyle(.motialPrimaryCompact)
            }
        case .app: Button { go(.wifi) } label: { Label("It's open", systemImage: "arrow.right") }.buttonStyle(.motialPrimaryCompact)
        case .wifi: Button { go(.connect) } label: { Label("Same Wi-Fi", systemImage: "arrow.right") }.buttonStyle(.motialPrimaryCompact)
        case .connect:
            HStack(spacing: Motial.Space.m) {
                Button("Drive without it") { finish(false) }.buttonStyle(.motialSecondary)
                Button { go(.strap) } label: { Label("Next", systemImage: "arrow.right") }
                    .buttonStyle(.motialPrimaryCompact).disabled(!link.connected)
            }
        case .strap: Button { go(.range) } label: { Label("It's on", systemImage: "arrow.right") }.buttonStyle(.motialPrimaryCompact)
        case .range: Button { go(.ready) } label: { Label("Done", systemImage: "arrow.right") }
                .buttonStyle(.motialPrimaryCompact).disabled(!triedPedal)
        case .ready:
            Button { finish(true) } label: { Label(finishTitle, systemImage: "steeringwheel") }.buttonStyle(.motialPrimaryCompact)
        }
    }

    private func page(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Motial.Space.l) {
            Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(Motial.pulse)
            Text(title).font(.motialTitle)
            Text(text).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Flow

    private func go(_ s: Step) {
        step = s
        say(s)
    }

    private func finish(_ withPhone: Bool) {
        var st = model.settings; st.pedalSetupDone = true; model.settings = st
        onFinish(withPhone)
    }

    /// The coach reads each step aloud in the app's one voice. Every line here already has a Kokoro af_heart
    /// clip in Resources/Voice (reused sentences); the Wi-Fi and searching screens are text only.
    private func say(_ s: Step, prefix: String = "") {
        let line: String
        switch s {
        case .intro: line = "Point your toes down slowly to drive, bring them back up slowly to ease off before the gold corners."
        case .app: line = "Open Motial Pedal on your iPhone, or watch the demo lap."
        case .wifi, .connect: line = ""
        case .strap: line = "Strap your iPhone to the top of your foot with a sports armband. Sit on a sturdy chair with your back supported."
        case .range: line = "Move only within a comfortable range. Point your toes down slowly."
        case .ready: line = "Whenever you're ready: point your toes down slowly."
        }
        let text = prefix.isEmpty ? line : prefix + " " + line
        guard !text.isEmpty else { SoundManager.shared.stopVoice(); return }
        SoundManager.shared.say(text, interrupt: true)
    }
}
