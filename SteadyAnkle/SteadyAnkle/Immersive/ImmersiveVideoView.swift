import SwiftUI
import RealityKit
import AVFoundation

/// Plays a real-person demonstration video fully immersively.
/// visionOS 26+: 180°/360°/wide-FOV videos with Apple Projected Media Profile (Insta360, GoPro MAX, Canon EOS VR…)
/// and spatial videos (iPhone 15 Pro and later, Vision Pro) are projected natively by RealityKit.
/// Earlier systems show the same file on a large stereo screen.
struct ImmersiveVideoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var player: AVPlayer?
    @State private var playing = true

    var body: some View {
        RealityView { content, attachments in
            guard let url = model.videoToPlay else { return }
            let p = AVPlayer(url: url)
            let entity = Entity()
            var video = VideoPlayerComponent(avPlayer: p)
            video.desiredViewingMode = .stereo
            #if compiler(>=6.2)
            if #available(visionOS 26.0, *) {
                video.desiredImmersiveViewingMode = .full
            }
            #endif
            entity.components.set(video)
            entity.position = [0, 1.4, -2.2]
            entity.scale = [1.6, 1.6, 1.6]
            content.add(entity)
            if let controls = attachments.entity(for: "controls") {
                controls.position = [0, 0.85, -0.9]
                controls.orientation = simd_quatf(angle: -0.5, axis: [1, 0, 0])
                content.add(controls)
            }
            p.play()
            player = p
            SoundManager.shared.stopAmbience()
        } attachments: {
            Attachment(id: "controls") {
                HStack(spacing: 16) {
                    Button {
                        playing.toggle()
                        if playing { player?.play() } else { player?.pause() }
                    } label: { Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") }
                    Button {
                        player?.seek(to: .zero); player?.play(); playing = true
                    } label: { Label("Replay", systemImage: "gobackward") }
                    Button(role: .destructive) {
                        Task { await close() }
                    } label: { Label("Close", systemImage: "xmark") }
                }
                .padding(16)
                .glassBackgroundEffect()
            }
        }
        .onDisappear {
            player?.pause()
            model.immersiveOpen = false
        }
    }

    private func close() async {
        player?.pause()
        model.videoToPlay = nil
        await dismissImmersiveSpace()
    }
}
