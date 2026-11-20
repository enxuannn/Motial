import SwiftUI
import WebKit

/// YouTube's official embedded player inside the app (streams; nothing is downloaded).
struct YouTubeEmbed: UIViewRepresentable {
    let videoID: String
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        load(web)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    private func load(_ web: WKWebView) {
        // The embed needs a page origin (YouTube refuses embeds without a referrer), so wrap it in a tiny page.
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent}iframe{border:0;width:100%;height:100%;border-radius:18px}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
          referrerpolicy="strict-origin-when-cross-origin"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}

/// "Watch a physio demo" card: a real physiotherapist demonstrating the exercise, credited to their channel.
struct PhysioDemoCard: View {
    let exerciseID: String
    @State private var playing = false
    var body: some View {
        if let d = PhysioDemos.byExercise[exerciseID] {
            Card {
                Label("Watch a physio demo", systemImage: "play.rectangle.fill").font(.headline)
                if playing {
                    YouTubeEmbed(videoID: d.videoID)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Button { playing = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.title).font(.callout.weight(.semibold)).lineLimit(2)
                                Text(d.channel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain).hoverEffect(.highlight)
                }
                Text("Video by \(d.channel) on YouTube. Needs an internet connection.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
