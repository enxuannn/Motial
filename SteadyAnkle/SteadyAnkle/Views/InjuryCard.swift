import SwiftUI

/// "Your injury", built to be read at a glance: the sprain type, the ligament(s) as small tiles, then "avoid" and
/// "fine to do" as short picture cards. Every card holds two to four words; tap one for the full sentence.
/// Sources and the disclaimer sit one tap away.
struct InjuryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var compact = false
    @State private var detail: Detail?
    @State private var showSources = false

    struct Detail: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let text: String
        let symbol: String
        let tint: Color
    }

    var body: some View {
        if let p = model.profile {
            let sites = ClinicalEngine.injurySites(p, uploads: model.uploads)
            let avoid = ClinicalEngine.avoid(model.stage, p)
            let ok = ClinicalEngine.okToDo(model.stage, p)
            VStack(alignment: .leading, spacing: Motial.Space.l) {
                // 1. what it is
                HStack(alignment: .center, spacing: Motial.Space.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR INJURY").font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.pulse)
                        Text(p.type.name).font(.motialSection)
                        Text(p.type.typicalRecovery).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Motial.Space.m)
                    Button {
                        model.anatomyMode = .myInjury
                        openWindow(id: "anatomy")
                    } label: { Label("See it in 3D", systemImage: "cube.transparent") }
                        .buttonStyle(.motialPrimaryCompact)
                }

                // 2. where it hurts: one tile per structure
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Motial.Space.m) {
                        ForEach(sites.prefix(compact ? 2 : 6)) { s in
                            tile(symbol: "scope", tint: Motial.coral, title: s.title.components(separatedBy: ",").first ?? s.title,
                                 caption: s.title.contains(",") ? s.title.components(separatedBy: ", ").dropFirst().joined(separator: ", ") : "Tap to learn",
                                 width: 210) {
                                detail = Detail(title: s.title, text: s.why, symbol: "scope", tint: Motial.coral)
                            }
                        }
                    }
                }

                // 3. avoid / fine: short picture cards
                adviceRow("Avoid for now", symbol: "hand.raised.fill", tint: Motial.caution, items: Array(avoid.prefix(compact ? 4 : 8)))
                adviceRow("Fine to do", symbol: "checkmark.circle.fill", tint: Motial.pulse, items: ok)

                HStack {
                    Button { showSources = true } label: { Label("Sources", systemImage: "text.book.closed") }
                        .buttonStyle(.motialSecondary)
                    Spacer()
                    Text("Guidance, not a diagnosis.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Motial.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
            .sheet(item: $detail) { d in
                VStack(alignment: .leading, spacing: Motial.Space.l) {
                    Image(systemName: d.symbol).font(.largeTitle).foregroundStyle(d.tint)
                    Text(d.title).font(.motialTitle)
                    Text(d.text).font(.title3).fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { detail = nil }.buttonStyle(.motialPrimaryCompact)
                }
                .padding(Motial.Space.xxl)
                .frame(width: 560, alignment: .leading)
            }
            .sheet(isPresented: $showSources) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Motial.Space.l) {
                            EvidenceList(ids: sourceIDs(p))
                            Text("General guidance from clinical guidelines, not a diagnosis. Your doctor or physiotherapist's advice comes first.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(Motial.Space.xxl)
                    }
                    .navigationTitle("Sources")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showSources = false } } }
                }
                .frame(minWidth: 720, minHeight: 560)
            }
        }
    }

    private func sourceIDs(_ p: PatientProfile) -> [String] {
        var ids = ["jospt2021", "doherty2017", "peacelove", "nhs111", "iac2014", "falls2022", "ottawa"]
        if p.isHighAnkle { ids.insert("williams2010", at: 1) }
        if p.type == .medial { ids.insert("deltoidNCH", at: 1) }
        return ids
    }

    private func adviceRow(_ title: String, symbol: String, tint: Color, items: [ActivityAdvice]) -> some View {
        VStack(alignment: .leading, spacing: Motial.Space.s) {
            Label(title, systemImage: symbol).font(.motialHeadline).foregroundStyle(tint)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Motial.Space.m) {
                    ForEach(items) { a in
                        tile(symbol: a.symbol, tint: tint, title: a.title, caption: nil, width: 150) {
                            detail = Detail(title: a.title, text: a.text, symbol: a.symbol, tint: tint)
                        }
                    }
                }
            }
        }
    }

    /// A small picture card: a big symbol and two to four words. Tap for the full sentence.
    private func tile(symbol: String, tint: Color, title: String, caption: String?, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                    .frame(width: 44, height: 44).background(tint.opacity(0.16), in: Circle())
                Text(title).font(.callout.weight(.semibold)).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(Motial.Space.m)
            .frame(width: width, alignment: .leading)
            .background(Motial.surfaceRaised, in: RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: Motial.Radius.tile))
        .hoverEffect(.lift)
        .accessibilityHint("Shows more")
    }
}
