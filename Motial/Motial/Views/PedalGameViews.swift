import SwiftUI

// MARK: - Motial Pedal pairing (iPhone ↔ Vision Pro)

/// Live status of the Motial Pedal iPhone link, with a plain explanation of how it connects.
struct PhoneLinkCard: View {
    var compact = false
    private var link: ShinLink { ShinLink.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(link.connected ? Color.green.opacity(0.25) : Color.white.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: link.connected ? "iphone.radiowaves.left.and.right" : "iphone")
                        .font(.title3).foregroundStyle(link.connected ? .green : .secondary)
                        .symbolEffect(.pulse, isActive: !link.connected)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.connected ? "iPhone connected" : "Waiting for your iPhone…").font(.headline)
                    Text(link.connected ? (link.realSensor ? "Your foot is the pedal" : "Practice slider on the phone")
                                        : "Open Motial Pedal on your iPhone")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if link.connected { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green) }
            }
            if !compact && !link.connected {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Same Wi-Fi: your iPhone and Vision Pro talk directly, nothing goes online.", systemImage: "wifi")
                    Label("Open Motial Pedal. It finds this Vision Pro by itself.", systemImage: "magnifyingglass")
                    Label("Allow \u{201C}Local Network\u{201D} the first time on both devices.", systemImage: "checkmark.shield")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(compact ? 12 : 16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { ShinLink.shared.start() }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal "toes down" meter.
struct PedalBar: View {
    let level: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Color(red: 1, green: 0.72, blue: 0.4)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, geo.size.width * level))
                }
            }
            .frame(height: 14)
            HStack {
                Label("Resting", systemImage: "arrow.up").font(.caption)
                Spacer()
                Label("Toes down", systemImage: "arrow.down").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .animation(.smooth(duration: 0.12), value: level)
        .accessibilityLabel("Pedal \(Int(level * 100)) percent")
    }
}

// MARK: - Get ready (before a pedal game)

struct PedalBriefing: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: SessionController
    @State private var practised = false
    @State private var showSetup = false
    @State private var inlineSetup = false
    private var link: ShinLink { ShinLink.shared }

    var body: some View {
        if inlineSetup {
            // one step at a time, right here in the session panel
            PedalSetupFlow(onFinish: { _ in inlineSetup = false }, finishTitle: "Back to the drive")
        } else if let ex = session.exercise, let d = session.dosage {
            let cockpit = ex.kind == .game(.cockpitDrive)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: ex.symbol).font(.largeTitle).foregroundStyle(Theme.accent)
                        .frame(width: 72, height: 72).background(Theme.accent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.title).font(.largeTitle.bold())
                        Text("\(d.text) · about a minute each").font(.title3).foregroundStyle(.secondary)
                    }
                }
                // One clear button that starts the experience straight away (works without the iPhone: demo drive).
                Button { session.startSet() } label: {
                    Label("Activate Experience", systemImage: "visionpro").frame(maxWidth: .infinity)
                }
                .buttonStyle(.motialPrimary)
                .disabled(session.phase != .intro)
                if ex.seated && !link.connected {
                    HStack(spacing: 12) {
                        Label(cockpit ? "No iPhone? Cruise assist drives for you." : "No iPhone? It plays as a demo.", systemImage: "iphone.slash")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button { inlineSetup = true } label: { Label("Connect iPhone pedal", systemImage: "iphone") }
                            .buttonStyle(.motialSecondary)
                    }
                }
                LastRunLine(exerciseID: ex.id)
                if cockpit {
                    Label("Sit with your back supported and look ahead. Feeling dizzy? Tap STOP.", systemImage: "chair.fill")
                        .font(.callout).foregroundStyle(Motial.caution)
                }

                // Progressive disclosure: set-up and learning stay one tap away so the panel reads at a glance.
                DisclosureGroup(isExpanded: $showSetup) {
                    VStack(alignment: .leading, spacing: 14) {
                        if ex.seated {
                            step(1, "Connect your iPhone", done: link.connected) { PhoneLinkCard(compact: link.connected) }
                            step(2, "Try the pedal", done: practised) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(link.connected ? "Point your toes down slowly, then bring them back up."
                                                        : "Once connected, point your toes down and watch the bar fill.")
                                        .font(.callout).foregroundStyle(.secondary)
                                    PedalBar(level: Double(link.connected ? link.value : 0))
                                }
                            }
                        } else {
                            step(1, "Fingertips on your support", done: true) {
                                Text("A wall or the back of a sturdy chair, within reach the whole time.").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        if cockpit {
                            step(ex.seated ? 3 : 2, "Hands on the wheel", done: session.handTracking) {
                                Text(session.handTracking ? "Hold both hands up as if on a wheel and move them left or right to steer. Rest your arms any time: lane assist steers."
                                                          : "Hand tracking isn't available here, so lane assist will steer for you.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Label("What you'll train", systemImage: "graduationcap.fill").font(.headline).foregroundStyle(Theme.accent)
                            Text(ex.purpose).font(.callout)
                            MusclesView(exercise: ex, compact: true)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Label(ex.seated ? "iPhone pedal, steering and what it trains" : "Set-up and what it trains", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }

                HStack {
                    Button("Skip") { session.skipExercise() }
                    Spacer()
                }
            }
            .onChange(of: link.value) { _, v in if v > 0.6 { practised = true } }
            .onAppear { if ex.seated { ShinLink.shared.start() } }
        }
    }

    private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.white.opacity(0.15)).frame(width: 30, height: 30)
                if done { Image(systemName: "checkmark").font(.caption.bold()) } else { Text("\(n)").font(.callout.bold()) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}

// MARK: - In game

struct PedalGameHUD: View {
    @Bindable var session: SessionController

    var body: some View {
        if let ex = session.exercise, let d = session.dosage {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(ex.title).font(.title2.bold())
                    Spacer()
                    Text("Round \(session.setNumber) of \(d.sets)").font(.headline).foregroundStyle(.secondary)
                }
                // big glanceable numbers (the cockpit shows these on its own dashboard gauges instead)
                if ex.kind != .game(.cockpitDrive) {
                HStack(spacing: 10) {
                    ForEach(session.gameStats, id: \.self) { st in
                        VStack(spacing: 4) {
                            Text(st.value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                                .contentTransition(.numericText())
                            Text(st.label).font(.caption).foregroundStyle(.secondary)
                            if let p = st.progress {
                                ProgressView(value: min(1, max(0, p))).tint(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                PedalBar(level: Double(session.pedalLevel ?? 0))
                } else {
                    Label("Speed, ankle, orbs and gates are on your dashboard. Coaching appears on the windscreen.", systemImage: "gauge.with.needle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let f = session.feedback, ex.kind != .game(.cockpitDrive) {
                    Text(f).font(.title3.bold()).foregroundStyle(.yellow).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let tip = session.learnTip {
                    Label(tip, systemImage: "graduationcap.fill")
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if ex.seated { PhoneLinkCard(compact: true) }
                HStack {
                    Button { session.togglePause() } label: {
                        Label(session.paused ? "Resume" : "Pause", systemImage: session.paused ? "play.fill" : "pause.fill")
                    }
                    Spacer()
                    Button("Skip") { session.skipExercise() }
                }
                .controlSize(.small)
            }
        }
    }
}
