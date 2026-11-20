import SwiftUI

@main
struct SteadyShinApp: App {
    var body: some Scene {
        WindowGroup { ShinView() }
    }
}

/// Motial brand v2 (matches the Vision Pro app): ink canvas, Pulse mint accent, chalk type.
private enum Brand {
    static let ink = Color(red: 0.051, green: 0.055, blue: 0.047)        // #0D0E0C
    static let graphite = Color(red: 0.13, green: 0.14, blue: 0.13)
    static let pulse = Color(red: 0.298, green: 0.949, blue: 0.690)      // #4CF2B0
    static let chalk = Color(red: 0.949, green: 0.949, blue: 0.925)      // #F2F2EC
    static let ember = Color(red: 1.0, green: 0.48, blue: 0.36)
    static let surface = Color.white.opacity(0.06)
    // legacy names used by the pieces below
    static let night = ink
    static let lantern = pulse
    static let teal = pulse
}

private extension Font {
    static var eyebrow: Font { .system(size: 12, weight: .heavy).width(.expanded) }
}

/// The Motial stride mark: a forward-leaning parallelogram.
private struct StrideMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = r.width * 0.35
        p.move(to: CGPoint(x: r.minX + k, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - k, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

private struct Canvas: View {
    var body: some View {
        ZStack {
            Brand.ink
            RadialGradient(colors: [Brand.pulse.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct ShinView: View {
    @State private var model = ShinModel.shared
    @AppStorage("motial.pedal.onboarded") private var onboarded = false
    @State private var showHowItConnects = false

    var body: some View {
        ZStack {
            Canvas()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    LinkPill(model: model)
                    Gauge(value: model.value, status: model.status)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    if !model.sensorAvailable || model.usePractice { practiceCard }
                    setupCard
                    LearnCard(motion: model.ankleMotion)
                    safetyCard
                    Button { showHowItConnects = true } label: { Label("How does it connect?", systemImage: "questionmark.circle") }
                        .font(.footnote.weight(.semibold))
                        .tint(Brand.chalk.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Brand.chalk)
        .tint(Brand.pulse)
        .preferredColorScheme(.dark)
        .task { model.start() }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            PedalOnboarding { onboarded = true }
        }
        .sheet(isPresented: $showHowItConnects) {
            ConnectExplainer().padding(24).presentationDetents([.medium, .large]).preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("MOTIAL").font(.system(size: 15, weight: .black).width(.expanded))
                StrideMark().fill(Brand.pulse).frame(width: 12, height: 13)
                Text("PEDAL").font(.eyebrow).tracking(1.4).foregroundStyle(Brand.pulse)
            }
            .padding(.top, 14)
            Text("Your ankle drives.").font(.system(size: 34, weight: .bold))
            Text("Point your toes down to accelerate in Motial on Apple Vision Pro. Ease off slowly for the gates.")
                .font(.subheadline)
                .foregroundStyle(Brand.chalk.opacity(0.7))
        }
    }

    private var practiceCard: some View {
        GlassCard {
            Label(model.sensorAvailable ? "Practice mode" : "No motion sensor here", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text(model.sensorAvailable ? "Slide instead of strapping the phone on."
                                       : "This device (for example the Simulator) has no motion sensor. Slide to press the pedal.")
                .font(.footnote).foregroundStyle(.secondary)
            Slider(value: $model.practice, in: 0...1) {
                Text("Toes down")
            } minimumValueLabel: {
                Image(systemName: "arrow.up").font(.caption)
            } maximumValueLabel: {
                Image(systemName: "arrow.down").font(.caption)
            }
            .tint(Brand.pulse)
            if model.sensorAvailable {
                Button("Use my ankle instead") { model.usePractice = false }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var setupCard: some View {
        SetupStepper(model: model)
    }

    private var safetyCard: some View {
        GlassCard {
            Label("Stay seated the whole time", systemImage: "chair.fill").font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ember)
            Text("Move slowly and only in a comfortable range. Stop if pain rises above 5/10 or the ankle feels unstable. Singapore: emergency 995 · NurseFirst nurse helpline 6262 6262.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: Pieces

/// Pedal setup, one step per screen: strap on → rest flat → toes down → ready.
/// Calibration method: resting and comfortable end-range plantarflexion, the active range used in
/// seated ankle ROM work (JOSPT Ankle Ligament Sprain CPG 2021; Doherty 2017).
private struct SetupStepper: View {
    let model: ShinModel
    @AppStorage("motial.pedal.strapped") private var strapped = false
    @State private var reviewing: Int? = nil

    private var autoStep: Int {
        if !strapped { return 0 }
        if !model.hasRest { return 1 }
        if !model.hasRange { return 2 }
        return 3
    }
    private var step: Int { reviewing ?? autoStep }
    private var sensorLive: Bool { model.sensorAvailable && !model.usePractice }

    var body: some View {
        GlassCard {
            HStack {
                Text(step < 3 ? "SET UP · STEP \(step + 1) OF 3" : "SET UP · READY")
                    .font(.eyebrow).tracking(1.4).foregroundStyle(Brand.pulse)
                Spacer()
                if step > 0 {
                    Button { withAnimation(.smooth) { reviewing = step - 1 } } label: {
                        Label("Back", systemImage: "chevron.left")
                    }.font(.footnote)
                }
            }
            ProgressDots(count: 3, current: step)
            Group {
                switch step {
                case 0: strapStep
                case 1: restStep
                case 2: rangeStep
                default: readyStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
            if sensorLive && step < 3 {
                Button("Try with a slider instead") { model.usePractice = true }.font(.footnote)
            }
        }
        .animation(.smooth, value: step)
    }

    private var strapStep: some View {
        StepBody(symbol: "figure.seated.side", title: "Strap the phone on",
                 detail: "Sit on a sturdy chair. Use a sports armband around the top of your foot, screen facing up.") {
            Button { reviewing = nil; strapped = true } label: { Label("It's on, next", systemImage: "arrow.right") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(Brand.ink)
        }
    }

    private var restStep: some View {
        StepBody(symbol: "pause.circle", title: "Rest your foot flat",
                 detail: "Relax your ankle with your heel on the floor, then tap.") {
            Button { model.setRest(); reviewing = nil } label: { Label("Set resting position", systemImage: "pause.circle") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(Brand.ink)
                .disabled(!sensorLive)
        }
    }

    private var rangeStep: some View {
        StepBody(symbol: "arrow.down.circle", title: "Point your toes down",
                 detail: "Only as far as feels comfortable, with no pain above 3/10. Hold it there and tap.") {
            Button { model.setFullRange(); reviewing = nil } label: { Label("Set full range", systemImage: "arrow.down.circle") }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(Brand.ink)
                .disabled(!sensorLive)
        }
    }

    private var readyStep: some View {
        StepBody(symbol: "checkmark.circle.fill", title: "Ready to drive",
                 detail: "Your comfortable range is \(Int(model.rangeDegrees.rounded()))°. Start Dawn Drive on Vision Pro.") {
            Button("Set up again") { model.resetCalibration(); strapped = false; reviewing = nil }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

private struct StepBody<Action: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var action: Action
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Brand.pulse)
            Text(title).font(.title3.weight(.bold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            action.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? Brand.pulse : .white.opacity(0.15)).frame(height: 4)
            }
        }
        .accessibilityLabel("Step \(min(current + 1, count)) of \(count)")
    }
}

private struct LinkPill: View {
    let model: ShinModel
    var body: some View {
        HStack(spacing: 10) {
            switch model.link {
            case .connected:
                Circle().fill(Brand.pulse).frame(width: 9, height: 9)
                Text("Connected to \(model.visionName ?? "Vision Pro")")
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Connecting to \(model.visionName ?? "Vision Pro")…")
            case .searching:
                ProgressView().controlSize(.small)
                Text("Looking for Motial on your Vision Pro…")
            case .waiting(let why):
                Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                Text(why).lineLimit(3)
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.smooth, value: model.link)
    }
}

/// A round dial: Pulse mint fills from resting (top) clockwise toward full toes-down.
private struct Gauge: View {
    let value: Double
    let status: String?
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.001, value))
                .stroke(Brand.pulse, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Brand.pulse.opacity(0.45), radius: 12)
            VStack(spacing: 4) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Brand.pulse)
                    .rotationEffect(.degrees(value * 35))
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 60, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(value > 0.15 ? "TOES DOWN" : "RESTING")
                    .font(.eyebrow).tracking(1.4)
                    .foregroundStyle(Brand.chalk.opacity(0.6))
                if let status {
                    Text(status)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Brand.pulse, in: Capsule())
                        .padding(.top, 6)
                }
            }
        }
        .frame(width: 250, height: 250)
        .animation(.smooth(duration: 0.15), value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Toes down \(Int(value * 100)) percent")
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

private struct StepRow<Action: View>: View {
    let n: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Brand.teal : .white.opacity(0.15)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Brand.night) }
                else { Text("\(n)").font(.caption.bold()) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                action
            }
        }
    }
}

extension StepRow where Action == EmptyView {
    init(n: Int, done: Bool, title: String, detail: String) {
        self.init(n: n, done: done, title: title, detail: detail) { EmptyView() }
    }
}


// MARK: - Learning

/// Live "what's working" card: names the muscles doing the job right now, so every press teaches something.
private struct LearnCard: View {
    let motion: ShinModel.Motion
    private let rows: [(ShinModel.Motion, String, String, String)] = [
        (.pushing, "arrow.down.circle.fill", "Toes down", "Calf and Achilles push, the same push-off you use to walk."),
        (.easing, "arrow.up.circle.fill", "Easing off slowly", "Your shin muscle (tibialis anterior) controls the foot. Slow is strong."),
        (.holding, "pause.circle.fill", "Holding", "The peroneals on the outside of the ankle keep it from rolling."),
    ]
    var body: some View {
        GlassCard {
            Label("What's working", systemImage: "graduationcap.fill").font(.headline)
            ForEach(rows, id: \.2) { r in
                let on = r.0 == motion
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: r.1).font(.title2).foregroundStyle(on ? Brand.lantern : .white.opacity(0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.2).font(.subheadline.weight(.semibold))
                        Text(r.3).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(on ? Brand.lantern.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.smooth, value: on)
            }
        }
    }
}

// MARK: - Onboarding

private struct ConnectExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "iphone").font(.system(size: 40))
                Image(systemName: "wifi").font(.title).foregroundStyle(Brand.teal)
                    .symbolEffect(.variableColor.iterative)
                Image(systemName: "visionpro").font(.system(size: 40))
            }
            .frame(maxWidth: .infinity)
            Text("How it connects").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                Label("Put both on the same Wi-Fi.", systemImage: "wifi")
                Label("On Vision Pro, open Motial and start a pedal game (Dawn Drive or Lantern Glide).", systemImage: "visionpro")
                Label("This app finds it by itself and connects. You'll see \u{201C}Connected\u{201D}.", systemImage: "link")
                Label("Allow \u{201C}Local Network\u{201D} the first time you're asked, on both devices.", systemImage: "checkmark.shield")
                Label("They talk directly: nothing goes over the internet and nothing is stored.", systemImage: "lock.fill")
            }
            .font(.callout)
        }
    }
}

private struct PedalOnboarding: View {
    var done: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            Canvas()
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    pageView(symbol: "shoeprints.fill", title: "Your foot is the pedal",
                             text: "Motial Pedal turns your iPhone into the accelerator for Motial on Apple Vision Pro. Point your toes down to drive the car in Dawn Drive or glide the boat in Lantern Glide.").tag(0)
                    ConnectExplainer().padding(28).tag(1)
                    pageView(symbol: "graduationcap.fill", title: "Learn as you move",
                             text: "Toes down works your calf and Achilles. Bringing them up slowly trains your shin muscle to control the foot. Motial shows which muscle is working, live.").tag(2)
                    pageView(symbol: "figure.seated.side", title: "Strap it on, sit down",
                             text: "Use a sports armband around the top of your foot, screen up. Sit on a sturdy chair. Then set your resting position and your comfortable range.").tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button {
                    if page < 3 { withAnimation { page += 1 } } else { done() }
                } label: {
                    Text(page < 3 ? "Continue" : "Get started").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(Brand.pulse).foregroundStyle(Brand.ink)
                .padding(.horizontal, 24)
                if page < 3 { Button("Skip") { done() }.font(.footnote) }
            }
            .padding(.bottom, 20)
        }
        .preferredColorScheme(.dark)
    }

    private func pageView(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(Brand.lantern)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85))
        }
        .padding(32)
    }
}
