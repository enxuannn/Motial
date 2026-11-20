import SwiftUI

/// Asked before every session (unless the person chose "remember"): train in your own room, or in an
/// immersive scene. Steady never replaces the person's surroundings without asking.
struct SpaceChoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onChoose: (_ room: Bool, _ remember: Bool) -> Void
    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Where would you like to train?").font(.largeTitle.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonBorderShape(.circle)
            }
            HStack(alignment: .top, spacing: 20) {
                option(title: "My room", symbol: "house.fill",
                       text: "See your real space. Your coach stands in your room, and gentle effects appear on your floor as you step.",
                       note: "Best for standing work. You see furniture and your support.", art: nil) { onChoose(true, remember) }
                option(title: "Immersive scene", symbol: "mountain.2.fill",
                       text: "Train in \(model.settings.defaultEnvironment.title). A room scan checks your space first, and the Digital Crown brings your room back at any time.",
                       note: "Change the scene below.", art: Theme.art(for: model.settings.defaultEnvironment)) { onChoose(false, remember) }
            }
            HStack(spacing: 10) {
                Text("Scene").font(.headline)
                ForEach(EnvironmentKind.pickerCases) { e in
                    let on = model.settings.defaultEnvironment == e
                    Button { var s = model.settings; s.defaultEnvironment = e; model.settings = s } label: {
                        Image(Theme.art(for: e)).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48).clipShape(Circle())
                            .overlay(Circle().strokeBorder(on ? Color.white : .clear, lineWidth: 3))
                    }
                    .buttonStyle(.plain).buttonBorderShape(.circle).accessibilityLabel(e.title)
                }
                Spacer()
                Toggle("Remember my choice", isOn: $remember).fixedSize()
            }
            Text("You can switch between your room and the scene at any time during the session.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func option(title: String, symbol: String, text: String, note: String, art: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    if let art { Image(art).resizable().aspectRatio(contentMode: .fill) } else { Color.white.opacity(0.08) }
                    Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.white)
                        .frame(width: 80, height: 80).background(.ultraThinMaterial, in: Circle())
                }
                .frame(height: 150).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(title).font(.title2.bold())
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 26))
        .hoverEffect(.lift)
    }
}
