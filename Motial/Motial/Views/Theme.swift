import SwiftUI
import UIKit

/// Visual language: the Motial brand system (Brand.swift): App Store–style cover cards over the system glass,
/// large rounded type, generous spacing (visionOS HIG: 60 pt+ targets, hover feedback on every control).
enum Theme {
    static let accent = Motial.teal
    static let corner: CGFloat = Motial.Radius.hero
    static let cardFill = Motial.surface

    static func art(for stage: RehabStage) -> String {
        switch stage {
        case .protect, .load, .balance, .returnToActivity: return "art_golden_meadow"   // no water scenes on the session card
        }
    }
    static func art(for env: EnvironmentKind) -> String {
        if env.isSpace {
            let name = "art_" + env.imageName.dropFirst(4)
            return UIImage(named: name) != nil ? name : "art_golden_meadow"
        }
        switch env.flavor {
        case .dawnLake: return "art_dawn_lake"
        case .riverValley: return "art_river_valley"
        case .goldenMeadow: return "art_golden_meadow"
        case .auroraNight: return "art_aurora_night"
        }
    }
    static func gameSymbol(_ g: GameKind) -> String {
        switch g {
        case .balanceBloom: return "camera.macro"
        case .ballCatch: return "baseball.fill"
        case .riverStones: return "water.waves"
        case .rhythmSteps: return "music.note"
        case .lanternGlide: return "sailboat.fill"
        case .dawnDrive: return "car.fill"
        case .cockpitDrive: return "steeringwheel"
        case .wordGarden: return "character.cursor.ibeam"
        }
    }

    static func gameArt(_ g: GameKind) -> String {
        switch g {
        case .balanceBloom: return "art_dawn_lake"
        case .ballCatch: return "art_golden_meadow"
        case .riverStones: return "art_river_valley"
        case .rhythmSteps: return "art_aurora_night"
        case .lanternGlide: return "art_dawn_lake"
        case .dawnDrive: return "art_golden_meadow"
        case .cockpitDrive: return "art_golden_meadow"
        case .wordGarden: return "art_golden_meadow"
        }
    }
}

/// Large artwork card: scenery photo + scrim + text column + optional action.
/// Text and the optional figure sit in separate columns of an HStack, so nothing ever overlaps.
/// (No coach cut-outs in menus: the life-size coach appears only inside the training space.)
struct HeroCard<Accessory: View>: View {
    let art: String
    var symbol: String? = nil          // SF Symbol glyph shown above the eyebrow
    var figure: String? = nil          // optional illustration (used only for the anatomy card)
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var height: CGFloat = 300
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.title2).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(.ultraThinMaterial, in: Circle())
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
                Text(eyebrow.uppercased()).font(.motialEyebrow).foregroundStyle(Motial.gold).tracking(1.4)
                    .lineLimit(1)
                Text(title).font(.motialTitle).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(Motial.mist.opacity(0.9)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                accessory.padding(.top, 8)
            }
            .frame(maxWidth: 560, maxHeight: .infinity, alignment: .bottomLeading)
            Spacer(minLength: 0)
            if let figure {
                Image(figure).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: height * 0.9, maxHeight: height - 40)
                    .accessibilityHidden(true)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            // the artwork fills the card but is clipped to it and never takes taps, so it can't cover buttons on nearby cards
            CoverImage(name: art)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// Plan tile: the activity cover with its title on it, the dose underneath. Details (why, how, tags) live one tap
/// away on the exercise screen (progressive disclosure), so the plan reads at a glance.
struct ExerciseTile: View {
    let item: ClinicalEngine.PlanItem
    var index: Int? = nil
    var body: some View {
        let ex = item.exercise
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let index { Text("\(index)").font(.caption.weight(.heavy)).foregroundStyle(Motial.navy)
                        .frame(width: 26, height: 26).background(Motial.mist, in: Circle()) }
                    Spacer()
                    if case .game = ex.kind { Pill(text: "Game", symbol: "gamecontroller.fill", tint: Motial.gold) }
                }
                Spacer(minLength: 0)
                Text(ex.title).font(.motialHeadline).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.85)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
            .background { CoverImage(name: tileArt) }
            .clipped()
            HStack(spacing: 8) {
                Image(systemName: ex.seated ? "chair.fill" : "figure.stand").foregroundStyle(Motial.teal)
                Text(item.dosage.text + (item.level > 1 ? " · Level \(item.level)" : ""))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Motial.surface)
        .clipShape(RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous))
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ex.title), \(item.dosage.text)")
    }
    private var tileArt: String {
        // one distinct cover per activity (Assets: cover_<exerciseID>), falling back to the scene art
        let cover = "cover_\(item.exercise.id)"
        if UIImage(named: cover) != nil { return cover }
        if case .game(let g) = item.exercise.kind { return Theme.gameArt(g) }
        return Theme.art(for: RehabStage(rawValue: item.exercise.stages.lowerBound) ?? .load)
    }
}

/// Small tag for use on glass (not over photos).
struct Tag: View {
    let text: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.1), in: Capsule())
        .foregroundStyle(.secondary)
    }
}

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .white
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.35), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Circular progress ring with a centred value.
struct MetricRing: View {
    var progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 14
    var label: String
    var caption: String? = nil
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height)
                VStack(spacing: 0) {
                    Text(label).font(.system(size: d * 0.3, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.5)
                    if let caption {
                        Text(caption).font(.system(size: max(11, d * 0.11))).foregroundStyle(.secondary).lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(width: d - lineWidth * 2 - 8)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\(label) \($0)" } ?? label)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Large tappable tile for single-choice questions (onboarding).
struct ChoiceTile: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let symbol {
                        Image(systemName: symbol).font(.title2)
                            .frame(width: 52, height: 52)
                            .background(selected ? Theme.accent : Color.white.opacity(0.1), in: Circle())
                            .foregroundStyle(selected ? .black : .primary)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selected ? Theme.accent : .secondary)
                }
                Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(selected ? Theme.accent.opacity(0.2) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 26))
        .hoverEffect(.lift)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ChoiceGrid<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String
    var symbol: ((T) -> String)? = nil
    var columns = 2
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
            ForEach(options) { o in
                ChoiceTile(title: title(o), symbol: symbol?(o), selected: selection == o) { selection = o }
            }
        }
    }
}

extension HeroCard where Accessory == EmptyView {
    init(art: String, symbol: String? = nil, figure: String? = nil, eyebrow: String, title: String, subtitle: String? = nil, height: CGFloat = 300) {
        self.init(art: art, symbol: symbol, figure: figure, eyebrow: eyebrow, title: title, subtitle: subtitle, height: height) { EmptyView() }
    }
}
