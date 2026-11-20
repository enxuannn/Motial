import SwiftUI

/// 0 – 10 pain selector with traffic-light colours.
struct PainScale: View {
    @Binding var value: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0...10, id: \.self) { p in
                Button { value = p } label: {
                    Text("\(p)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(p == value ? color(p) : color(p).opacity(0.18)))
                        .foregroundStyle(p == value ? .white : .primary)
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .hoverEffect()
                .accessibilityLabel("Pain \(p) of 10")
                .accessibilityAddTraits(p == value ? .isSelected : [])
            }
        }
    }
    private func color(_ p: Int) -> Color {
        switch ClinicalEngine.zone(p) { case .green: return .green; case .amber: return .orange; case .red: return .red }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(value).font(.title.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 90, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct StageBadge: View {
    let stage: RehabStage
    var body: some View {
        Label(stage.title, systemImage: stage.symbol)
            .font(.subheadline.bold())
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(stage.tint.opacity(0.25), in: Capsule())
            .foregroundStyle(stage.tint)
    }
}

/// Four-stage journey indicator.
struct StageTrack: View {
    let current: RehabStage
    var body: some View {
        HStack(spacing: 8) {
            ForEach(RehabStage.allCases) { s in
                VStack(spacing: 6) {
                    Capsule().fill(s <= current ? s.tint : Color.secondary.opacity(0.25)).frame(height: 8)
                    Text(s.title).font(.caption2).foregroundStyle(s == current ? .primary : .secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(current.rawValue) of 4: \(current.title)")
    }
}

struct EvidenceList: View {
    let ids: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ids, id: \.self) { id in
                if let e = EvidenceLibrary.byID(id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.finding).font(.callout)
                        if let url = URL(string: e.url) {
                            Link(e.citation, destination: url).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(e.citation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct DisclaimerText: View {
    var body: some View {
        Text("Motial provides exercise guidance and education based on published clinical guidelines. It does not diagnose or replace care from a doctor or physiotherapist. If you are unsure, or symptoms worsen, seek professional advice.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
