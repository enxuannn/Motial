import SwiftUI

/// "Muscles working" chips plus "This helps you" goals for one exercise.
struct MusclesView: View {
    let exercise: Exercise
    var compact = false
    var onShow3D: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Label("Muscles working", systemImage: "figure.strengthtraining.functional").font(.headline).foregroundStyle(.orange)
                Spacer()
                if let onShow3D {
                    Button { onShow3D() } label: { Label("See in 3D", systemImage: "cube.transparent") }.controlSize(.small)
                }
            }
            FlowChips(items: exercise.muscles.map { compact ? $0.name : "\($0.name): \($0.role)" })
            if !compact {
                Text("Muscle roles: standard functional anatomy (BodyParts3D model). Activity goals follow the JOSPT 2021 guideline and the MGH protocol. Confirm your own goals with your physiotherapist.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !exercise.unlocks.isEmpty {
                Label("This helps you", systemImage: "flag.checkered").font(.headline).foregroundStyle(Theme.accent).padding(.top, 2)
                ForEach(exercise.unlocks.prefix(compact ? 1 : 3), id: \.self) { u in
                    Label(u, systemImage: "checkmark.circle").font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Simple wrapping chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t).font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.16), in: Capsule())
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); widest = max(widest, x)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
