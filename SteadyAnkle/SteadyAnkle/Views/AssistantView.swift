import SwiftUI

/// Chat with Steady. Type or use the keyboard's microphone to dictate; answers can be read aloud.
struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var assistant = SteadyAssistant()
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = ["What's my plan today?", "My ankle hurts, should I keep going?",
                               "When can I start hopping?", "What is the ATFL?", "How long will recovery take?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            intro
                            ForEach(assistant.messages) { m in bubble(m).id(m.id) }
                            if assistant.thinking { ProgressView().padding(.leading, 8) }
                        }
                        .padding(24)
                    }
                    .onChange(of: assistant.messages.count) { _, _ in
                        if let last = assistant.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { send(s) }.buttonStyle(.bordered)
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 10)
                }.scrollIndicators(.hidden)
                HStack(spacing: 12) {
                    TextField("Ask about your ankle, your plan or an exercise", text: $draft)
                        .textFieldStyle(.roundedBorder).focused($focused)
                        .onSubmit { send(draft) }
                    Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || assistant.thinking)
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
            .navigationTitle("Ask Motial")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { SoundManager.shared.stopVoice(); dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: Binding(get: { model.settings.assistantVoice ?? true },
                                         set: { v in var s = model.settings; s.assistantVoice = v; model.settings = s })) {
                        Label("Voice", systemImage: "speaker.wave.2")
                    }.toggleStyle(.button)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(assistant.usingAppleIntelligence ? "On-device Apple Intelligence" : "Motial coach", systemImage: "sparkles")
                .font(.headline).foregroundStyle(Theme.accent)
            Text("Ask anything about your recovery. Answers use your plan and the clinical guidelines Motial is built on. Motial doesn't diagnose. For new or severe symptoms, contact a clinician.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Tip: say \u{201C}Hey Siri, start my ankle session in Motial\u{201D} or \u{201C}Log ankle pain in Motial\u{201D}.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bubble(_ m: SteadyAssistant.Message) -> some View {
        HStack {
            if m.fromUser { Spacer(minLength: 80) }
            Text(m.text)
                .padding(14)
                .background(m.fromUser ? Theme.accent.opacity(0.3) : Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 520, alignment: m.fromUser ? .trailing : .leading)
            if !m.fromUser { Spacer(minLength: 80) }
        }
    }

    private func send(_ text: String) {
        let t = text
        draft = ""
        Task { await assistant.ask(t, model: model) }
    }
}
