import SwiftUI

/// Shown before every immersive experience: where to train (the immersive scene is recommended, the room is
/// optional), a concise safety check, then one primary action: Activate Experience.
/// Replaces the old "Where would you like to train?" sheet.
struct ActivationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let title: String
    var showsPlaceChoice = true
    var needsSupport = false
    /// The immersive place offered (defaults to the chosen scene); experiences with their own world name it here.
    var immersivePlace: (title: String, art: String)? = nil
    /// Opens the experience; returns false (with a message) if it couldn't open.
    let activate: (_ room: Bool) async -> String?

    @State private var room = false
    @State private var cleared = false
    @State private var space = false
    @State private var support = false
    @State private var error: String?

    private var ready: Bool { cleared && space && (!needsSupport || support) }

    var body: some View {
        VStack(alignment: .leading, spacing: Motial.Space.xl) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased()).font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.gold)
                    Text("Before you begin").font(.motialTitle)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonBorderShape(.circle).accessibilityLabel("Close")
            }

            if showsPlaceChoice {
                HStack(spacing: Motial.Space.l) {
                    placeOption(room: false, title: "Immersive", badge: "Recommended",
                                detail: immersivePlace?.title ?? model.settings.defaultEnvironment.title,
                                art: immersivePlace?.art ?? Theme.art(for: model.settings.defaultEnvironment))
                    placeOption(room: true, title: "My room", badge: nil, detail: "Your real space", art: nil)
                }
                if !room && immersivePlace == nil { scenePicker }
            }

            VStack(alignment: .leading, spacing: Motial.Space.s) {
                Text("Quick safety check").font(.motialHeadline)
                SafetyRow(symbol: "shippingbox", title: "Nearby objects cleared", detail: "Furniture, cables and pets out of the way", on: $cleared)
                SafetyRow(symbol: "square.dashed", title: "Enough space", detail: "About 2 × 2 m around you", on: $space)
                if needsSupport {
                    SafetyRow(symbol: "chair.fill", title: "Support within reach", detail: "A sturdy chair, wall or bench", on: $support)
                }
            }

            HStack(spacing: Motial.Space.l) {
                ActivateExperienceButton(disabled: !ready || model.immersiveOpen) {
                    var st = model.settings
                    st.spaceChoice = room ? "room" : "immersive"; st.roomView = room
                    model.settings = st
                    if let e = await activate(room) { error = e } else { dismiss() }
                }
                if !ready {
                    Text("Tick each check to continue.").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Motial.caution) }
            if showsPlaceChoice && !room {
                Text("Turn the Digital Crown at any time to bring your room back.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(Motial.Space.xxl)
        .frame(width: 720)
        .fixedSize(horizontal: false, vertical: true)     // never compress the rows (they overlapped in a short sheet)
        .presentationSizing(.fitted)
        .onAppear { room = model.settings.spaceChoice == "room" }
    }

    private func placeOption(room value: Bool, title: String, badge: String?, detail: String, art: String?) -> some View {
        let on = room == value
        return Button { room = value } label: {
            HStack(spacing: Motial.Space.m) {
                ZStack {
                    if let art { Image(art).resizable().aspectRatio(contentMode: .fill) } else { Motial.dusk }
                    Image(systemName: value ? "house.fill" : "mountain.2.fill").font(.title2).foregroundStyle(.white)
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if let badge {
                        Text(badge.uppercased()).font(.motialEyebrow).tracking(1).foregroundStyle(Motial.teal)
                    }
                    Text(title).font(.motialHeadline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(on ? Motial.teal : .secondary)
            }
            .padding(Motial.Space.m)
            .frame(maxWidth: .infinity)
            .background(on ? Motial.teal.opacity(0.16) : Motial.surface, in: RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Motial.Radius.tile, style: .continuous).strokeBorder(on ? Motial.teal : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: Motial.Radius.tile))
        .hoverEffect(.lift)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Choose the scene: picture tiles with a name and one calming line each (every tile is a different place).
    private var scenePicker: some View {
        VStack(alignment: .leading, spacing: Motial.Space.s) {
            HStack {
                Text("Choose your scene").font(.motialHeadline)
                Spacer()
                Text("You can switch during the session").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Motial.Space.m) {
                    ForEach(EnvironmentKind.pickerCases) { e in
                        let on = model.settings.defaultEnvironment == e
                        Button { var s = model.settings; s.defaultEnvironment = e; model.settings = s } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(Theme.art(for: e)).resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 150, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        if on {
                                            Image(systemName: "checkmark.circle.fill").font(.title3)
                                                .foregroundStyle(Motial.ink, Motial.pulse).padding(6)
                                        }
                                    }
                                Text(e.title).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(e.calmNote).font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
                            }
                            .frame(width: 150, alignment: .leading)
                            .padding(8)
                            .background(on ? Motial.pulse.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Motial.pulse : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .buttonBorderShape(.roundedRectangle(radius: 18))
                        .hoverEffect(.lift)
                        .accessibilityLabel("\(e.title). \(e.calmNote)").accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Label("Natural, calm surroundings support recovery (Ulrich 1984).", systemImage: "leaf")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
