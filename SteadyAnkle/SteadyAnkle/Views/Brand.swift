import SwiftUI

// MARK: - Motial brand system
//
// Name: Motial. Tagline: Every Step Counts.
// One fixed palette, one type ramp, one spacing scale and a small set of reusable components, so every screen
// reads the same way. visionOS conventions: glass windows, large rounded type, 60 pt+ targets, a hover effect on
// every control, and one clear primary action per screen.

enum Motial {
    static let name = "Motial"
    static let tagline = "Every Step Counts"

    // Palette v2: Apple-native restraint (system glass, SF Pro, generous space) with a measured sport/fintech edge:
    // one signature colour (Pulse mint) that only means "act" or "progress", ink text on it, flat colour, no gradients.
    static let ink = Color(red: 0.051, green: 0.055, blue: 0.047)      // #0D0E0C  text on Pulse, scrims, chips
    static let chalk = Color(red: 0.949, green: 0.949, blue: 0.925)    // #F2F2EC  text on imagery
    static let pulse = Color(red: 0.298, green: 0.949, blue: 0.690)    // #4CF2B0  the one signature colour
    static let graphite = Color(red: 0.118, green: 0.125, blue: 0.110) // #1E201C  quiet surfaces
    static let ember = Color(red: 1.000, green: 0.416, blue: 0.239)    // #FF6A3D  games, energy (sparingly)
    static let lilac = Color(red: 0.729, green: 0.659, blue: 0.961)    // #BAA8F5  Lumi only
    // Semantic (pain traffic light and status)
    static let success = Color(red: 0.302, green: 0.827, blue: 0.541)  // #4DD38A
    static let caution = Color(red: 0.961, green: 0.643, blue: 0.271)  // #F5A445
    static let danger = Color(red: 1.000, green: 0.353, blue: 0.369)   // #FF5A5E

    // Older names, mapped onto the v2 palette so every screen follows it
    static var teal: Color { pulse }
    static var gold: Color { pulse }
    static var navy: Color { ink }
    static var mist: Color { chalk }
    static var dusk: Color { graphite }
    static var coral: Color { ember }

    // Surfaces on glass
    static let surface = Color.white.opacity(0.07)
    static let surfaceRaised = Color.white.opacity(0.11)

    // Spacing scale
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 32, xxxl: CGFloat = 48
    }
    // Corner radii
    enum Radius {
        static let tile: CGFloat = 22, card: CGFloat = 28, hero: CGFloat = 34
    }

    static func painColor(_ p: Int) -> Color {
        switch ClinicalEngine.zone(p) { case .green: return success; case .amber: return caution; case .red: return danger }
    }
}

// Type ramp v2: SF Pro, Apple-style bold titles in sentence case for reading comfort. The brand accent in type is
// small and deliberate: the wordmark and the eyebrows use heavy expanded capitals.
extension Font {
    static let motialDisplay = Font.system(size: 46, weight: .bold)
    static let motialTitle = Font.system(size: 30, weight: .bold)
    static let motialSection = Font.system(size: 22, weight: .bold)
    static let motialHeadline = Font.system(.title3).weight(.semibold)
    static let motialEyebrow = Font.system(.caption).weight(.heavy).width(.expanded)
}

// MARK: - Buttons

/// The one primary action on a screen: a flat Pulse capsule with ink text.
struct MotialPrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration, compact: compact)
    }

    /// `isEnabled` is read inside a View: read directly in a ButtonStyle it does not update reliably,
    /// which made disabled buttons look tappable.
    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(compact ? .headline.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(isEnabled ? Motial.ink : Color.white.opacity(0.45))
                .padding(.horizontal, compact ? 20 : 28)
                .frame(minHeight: compact ? 48 : 60)
                .background(Capsule().fill(isEnabled ? Motial.pulse : Color.white.opacity(0.10)))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.highlight, isEnabled: isEnabled)
        }
    }
}

/// Secondary actions: the quiet system glass capsule, never competing with the primary.
struct MotialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)))
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
    }
}

extension ButtonStyle where Self == MotialPrimaryButtonStyle {
    static var motialPrimary: MotialPrimaryButtonStyle { MotialPrimaryButtonStyle() }
    static var motialPrimaryCompact: MotialPrimaryButtonStyle { MotialPrimaryButtonStyle(compact: true) }
}
extension ButtonStyle where Self == MotialSecondaryButtonStyle {
    static var motialSecondary: MotialSecondaryButtonStyle { MotialSecondaryButtonStyle() }
}

/// "Activate Experience": the single way into every immersive experience. It guards against double activation
/// and shows a calm loading state while the space opens.
struct ActivateExperienceButton: View {
    var title = "Activate Experience"
    var compact = false
    var disabled = false
    let action: () async -> Void
    @State private var working = false

    var body: some View {
        Button {
            guard !working else { return }
            working = true
            Task { @MainActor in
                await action()
                working = false
            }
        } label: {
            HStack(spacing: 10) {
                if working {
                    ProgressView().controlSize(.small).tint(Motial.ink)
                    Text("Opening…")
                } else {
                    Image(systemName: "visionpro")
                    Text(title)
                }
            }
        }
        .buttonStyle(MotialPrimaryButtonStyle(compact: compact))
        .disabled(disabled || working)
        .accessibilityHint("Opens the immersive experience")
    }
}

// MARK: - Brand mark

/// Wordmark: MOTIAL in black expanded capitals, followed by the Pulse "stride" (a forward-leaning bar).
struct MotialWordmark: View {
    var size: CGFloat = 28
    var showTagline = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: size * 0.18) {
                Text(Motial.name.uppercased()).font(.system(size: size, weight: .black).width(.expanded)).tracking(-0.5)
                StrideMark().fill(Motial.pulse).frame(width: size * 0.5, height: size * 0.72)
            }
            if showTagline {
                Text(Motial.tagline.uppercased()).font(.motialEyebrow).tracking(1.6).foregroundStyle(.white.opacity(0.7))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Motial.name). \(Motial.tagline).")
    }
}

/// The brand mark: one forward-leaning stride, a parallelogram with soft corners (also on the app icon).
struct StrideMark: Shape {
    func path(in r: CGRect) -> Path {
        let lean = r.width * 0.45
        var p = Path()
        p.move(to: CGPoint(x: r.minX + lean, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - lean, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Cards

/// An immersive experience: cover image, clear title, one line, and Activate Experience.
struct ExperienceCard<Extra: View>: View {
    let cover: String
    let eyebrow: String
    let title: String
    let subtitle: String
    var locked: String? = nil
    var height: CGFloat = 330
    let activate: () async -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: Motial.Space.s) {
            Spacer(minLength: 0)
            Text(eyebrow.uppercased()).font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.pulse)
            Text(title).font(.motialTitle).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).font(.callout).foregroundStyle(Motial.mist.opacity(0.9)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            extra
            HStack {
                if let locked {
                    Label(locked, systemImage: "lock.fill").font(.callout.weight(.semibold)).foregroundStyle(Motial.mist)
                        .padding(.horizontal, 16).frame(minHeight: 48).background(.ultraThinMaterial, in: Capsule())
                } else {
                    ActivateExperienceButton(compact: true, action: activate)
                }
            }
            .padding(.top, Motial.Space.xs)
        }
        .padding(Motial.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background { CoverImage(name: cover) }
        .clipShape(RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
    }
}

extension ExperienceCard where Extra == EmptyView {
    init(cover: String, eyebrow: String, title: String, subtitle: String, locked: String? = nil, height: CGFloat = 330,
         activate: @escaping () async -> Void) {
        self.init(cover: cover, eyebrow: eyebrow, title: title, subtitle: subtitle, locked: locked, height: height,
                  activate: activate) { EmptyView() }
    }
}

/// Cover artwork with the brand scrim (navy, bottom-weighted) so titles always read. Never takes taps.
struct CoverImage: View {
    let name: String
    var body: some View {
        Color.clear.overlay {
            Image(name).resizable().aspectRatio(contentMode: .fill)
                .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.1),
                                                .init(color: Motial.ink.opacity(0.55), location: 0.5),
                                                .init(color: Motial.ink.opacity(0.92), location: 1)],
                                        startPoint: .top, endPoint: .bottom))
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Small rounded status chip (stage, streak, pain).
struct StatusChip: View {
    let text: String
    let symbol: String
    var tint: Color = Motial.pulse
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(.white)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Motial.ink.opacity(0.6), in: Capsule())
    }
}
