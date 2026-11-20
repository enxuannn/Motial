import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Today card that opens Return to Sport.
struct SportLabCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false
    var body: some View {
        HeroCard(art: "cover_bb_set_shot", symbol: "figure.basketball",
                 eyebrow: "Return to Sport",
                 title: "Sport Lab",
                 subtitle: "Relearn your sport's moves with the right technique: a 360° demo by a real person, then the coach on an immersive court.",
                 height: 260) {
            Button { open = true } label: {
                Label("Open Sport Lab", systemImage: "sportscourt.fill").font(.title3.bold()).padding(.horizontal, 14).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
        .sheet(isPresented: $open) {
            SportLabView(close: { open = false }).environment(model).frame(minWidth: 980, minHeight: 720)
        }
    }
}

struct SportLabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    var close: () -> Void
    @State private var sport: Sport = .basketball
    @State private var evidenceFor: SportDrill?
    @State private var activating = false
    @State private var importingFor: SportDrill?
    @State private var errorText: String?

    private var confidence: Int { model.state.checkIns.last?.confidence ?? 3 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Relearn your sport's moves with your life-size coach. Jumps open only with your physiotherapist's OK.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Picker("Sport", selection: $sport) {
                            ForEach(Sport.allCases) { s in Label(s.title, systemImage: s.symbol).tag(s) }
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 420)
                        Spacer()
                        // the one primary action stays in view (not below the drill grid)
                        ActivateExperienceButton(compact: true, disabled: openDrills.isEmpty || model.immersiveOpen) { activating = true }
                    }
                    if let e = errorText { Text(e).font(.caption).foregroundStyle(.orange) }
                    else if openDrills.isEmpty && !SportLibrary.drills(for: sport).isEmpty {
                        // say why the button is off, right next to it
                        Label("No drills are open at \(model.stage.title). They unlock as your ankle meets each stage's goals.", systemImage: "lock.fill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    let drills = SportLibrary.drills(for: sport)
                    if drills.isEmpty {
                        Card {
                            Label("\(sport.title) drills are coming next", systemImage: "hammer")
                                .font(.title3.bold())
                            Text("Basketball and badminton are ready now. Football drills are being prepared with a physiotherapist.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 18, alignment: .top)], spacing: 18) {
                            ForEach(drills) { d in drillTile(d) }
                        }
                    }
                    Label("Sport Lab supports, not replaces, your physiotherapist. Stop if the ankle gives way or pain goes above 5/10.", systemImage: "cross.case")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(32)
            }
            .navigationTitle("Sport Lab")
            .sheet(isPresented: $activating) {
                // Sunset Court is the recommended immersive place; the room stays optional.
                ActivationSheet(title: "Sport Lab", needsSupport: true, immersivePlace: ("Sunset Court", "exp_sport_lab")) { room in
                    await start(onCourt: !room)
                    return errorText
                }
                .environment(model).frame(width: 760)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: close) } }
            .sheet(item: $evidenceFor) { d in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Why this drill, and how it is taught").font(.title2.bold())
                            Text(d.technique.joined(separator: " ")).font(.callout).fixedSize(horizontal: false, vertical: true)
                            EvidenceList(ids: d.evidence)
                            Label("Motial supports, and never replaces, your physiotherapist.", systemImage: "cross.case")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(32)
                    }
                    .navigationTitle(d.title)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { evidenceFor = nil } } }
                }
                .frame(minWidth: 760, minHeight: 600)
            }
            .fileImporter(isPresented: Binding(get: { importingFor != nil }, set: { if !$0 { importingFor = nil } }),
                          allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) { result in
                guard let d = importingFor, case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                let name = "clinician_\(d.videoKey).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension)"
                let dest = AppModel.documents.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { model.setClinicianVideo(name, for: d.videoKey) }
                importingFor = nil
            }
        }
    }

    private var openDrills: [SportDrill] {
        guard let p = model.profile else { return [] }
        return SportLibrary.drills(for: sport).filter {
            ClinicalEngine.access($0, profile: p, stage: model.stage, latestPain: model.latestPain, confidence: confidence) == .open
        }
    }

    private func drillTile(_ d: SportDrill) -> some View {
        let access = model.profile.map { ClinicalEngine.access(d, profile: $0, stage: model.stage, latestPain: model.latestPain, confidence: confidence) } ?? .locked("")
        let hasVideo = model.clinicianVideoURL(for: d.videoKey) != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: d.symbol).font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(.ultraThinMaterial, in: Circle())
                Spacer()
                if d.requiresHopClearance { Pill(text: "Jumps", symbol: "arrow.up.to.line", tint: .orange) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            .background { Color.clear.overlay { Image(UIImage(named: "cover_\(d.id)") != nil ? "cover_\(d.id)" : "cover_play_\(d.sport.rawValue)").resizable().aspectRatio(contentMode: .fill).overlay(Color.black.opacity(0.15)) }.clipped().allowsHitTesting(false) }
            .clipped()
            VStack(alignment: .leading, spacing: 8) {
                Text(d.title).font(.title3.bold())
                Text(d.dosage.text + " · Stage \(d.stages.lowerBound)\(d.stages.count > 1 ? "–\(d.stages.upperBound)" : "")")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(d.technique.first ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                if case .locked(let why) = access {
                    Label(why, systemImage: "lock.fill").font(.caption).foregroundStyle(.orange).lineLimit(2, reservesSpace: true)
                } else {
                    Label("Open today", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green).lineLimit(2, reservesSpace: true)
                }
                Button { evidenceFor = d } label: {
                    Label("Clinical sources (\(d.evidence.count))", systemImage: "text.book.closed")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                HStack {
                    Label(hasVideo ? "360° demo ready" : "No 360° demo yet", systemImage: hasVideo ? "pano.fill" : "pano")
                        .font(.caption).foregroundStyle(hasVideo ? .primary : .secondary)
                    Spacer()
                    Button(hasVideo ? "Replace" : "Add video") { importingFor = d }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Add a 180°/360° (APMP) or spatial video of a physio or coach demonstrating this drill")
                }
            }
            .padding(16)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .opacity(access == .open ? 1 : 0.7)
    }

    private func start(onCourt: Bool) async {
        guard let p = model.profile, let first = openDrills.first else { return }
        let lab = SportLabController(profile: p, stage: model.stage, drills: openDrills, first: first, onCourt: onCourt, settings: model.settings)
        model.sportLab = lab
        model.sportRoomView = !onCourt
        SoundManager.shared.apply(model.settings)
        switch await openImmersiveSpace(id: "sportlab") {
        case .opened:
            model.immersiveOpen = true; errorText = nil
            close()
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
        default:
            model.sportLab = nil
            errorText = "Couldn't open Sport Lab. Close other immersive apps and try again."
        }
    }
}


/// Today card for Play Smart, tailored to the person's sport (or everyday life). Open from day one: it only teaches.
struct CourtSmartsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var errorText: String?

    private var sport: PlaySport { PlaySport.suggested(for: model.profile) }

    var body: some View {
        HeroCard(art: sport.cover, symbol: sport.symbol,
                 eyebrow: sport == .everyday ? "Move smart" : "Play smart · \(sport.title)",
                 title: sport == .everyday ? "Everyday moves, your ankle" : "Back to \(sport.title.lowercased())",
                 subtitle: sport.subtitle,
                 height: 340) {
            VStack(alignment: .leading, spacing: 14) {
                // One native segmented control (short names so all five fit in the card's text column)
                Picker("Sport", selection: Binding(get: { sport }, set: { choose($0) })) {
                    ForEach(PlaySport.allCases) { s in Text(s.shortTitle).tag(s) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 540)
                .padding(3)
                .background(.black.opacity(0.32), in: Capsule())     // keeps the sport names readable over bright skies
                HStack(spacing: 12) {
                    Button { Task { await open() } } label: {
                        Label("Watch and learn", systemImage: "play.rectangle.fill").font(.title3.bold())
                            .padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(model.immersiveOpen)
                    if let e = errorText { Text(e).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }

    private func choose(_ s: PlaySport) {
        guard var p = model.profile else { return }
        p.playSport = s
        model.updateProfile(p)
    }

    private func open() async {
        model.guideSport = sport
        switch await openImmersiveSpace(id: "courtguide") {
        case .opened:
            model.immersiveOpen = true; errorText = nil
            dismissWindow(id: "main"); dismissWindow(id: "anatomy")   // the 3D ankle would float over the session panels
        default:
            errorText = "Couldn't open. Close other immersive apps and try again."
        }
    }
}
