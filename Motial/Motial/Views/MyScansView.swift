import SwiftUI
import UniformTypeIdentifiers

/// "My X-rays & reports": add your own images or reports and explore them next to the 3D ankle.
/// Educational only. Steady explains the words in your report; it doesn't read or diagnose images.
struct MyScansSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var importing = false
    @State private var working = false
    @State private var selected: MedicalUpload?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "My X-rays & reports",
                              subtitle: "Add a photo of your X-ray or a PDF of your report, then look through your bones in 3D. Everything stays on this device.")
                Button { importing = true } label: {
                    Label(working ? "Reading…" : "Add", systemImage: "plus.viewfinder")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(working)
            }
            if !model.reportCautions.isEmpty {
                Label("Your report mentions \(model.reportCautions.map(\.term).joined(separator: ", ")). Follow your clinician's advice. Hopping stays locked until they clear you.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if model.uploads.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle.angled").font(.title).foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56).background(Theme.accent.opacity(0.15), in: Circle())
                    Text("No scans yet. When you add one, Motial finds the anatomy words in it (like ATFL or fibula), explains them, and lights them up on the 3D ankle.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(model.uploads) { u in
                        Button { selected = u } label: { UploadTile(upload: u) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in
            guard case .success(let url) = result else { return }
            working = true
            Task {
                if let u = await ReportReader.importFile(url) { model.addUpload(u); selected = u }
                working = false
            }
        }
        .sheet(item: $selected) { u in
            UploadDetailView(upload: u) {
                model.focusUploadID = u.id
                selected = nil
                openWindow(id: "anatomy")
            } onDelete: {
                model.removeUpload(u); selected = nil
            }
            .frame(minWidth: 820, minHeight: 640)
        }
    }
}

struct UploadTile: View {
    let upload: MedicalUpload
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let img = ReportReader.image(for: upload) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else { Color.black.opacity(0.3) }
            }
            .frame(height: 130).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(upload.title).font(.headline).lineLimit(1)
                Text("\(upload.kind == .xray ? "X-ray" : "Report") · \(upload.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(upload.findings.isEmpty ? "No anatomy terms found" : "\(upload.findings.count) terms explained")
                    .font(.caption).foregroundStyle(upload.findings.contains(where: \.caution) ? .orange : Theme.accent)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .hoverEffect(.lift)
    }
}

struct UploadDetailView: View {
    let upload: MedicalUpload
    var onExplore: () -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    if let img = ReportReader.image(for: upload) {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 360, maxHeight: 460)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What your \(upload.kind == .xray ? "X-ray" : "report") mentions").font(.title2.bold())
                        if upload.findings.isEmpty {
                            Text("Motial didn't find anatomy words in this file. You can still view it next to the 3D ankle and compare the bones.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upload.findings) { f in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(f.term, systemImage: f.caution ? "exclamationmark.triangle.fill" : "info.circle")
                                    .font(.headline).foregroundStyle(f.caution ? .orange : Theme.accent)
                                Text(f.meaning).font(.callout)
                            }
                        }
                        Text("This explains words, not your diagnosis. Your doctor or physiotherapist interprets your scans.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button { onExplore() } label: { Label("See it in 3D", systemImage: "cube.transparent") }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                            Button { SoundManager.shared.say(spoken) } label: { Label("Read aloud", systemImage: "speaker.wave.2") }
                            Spacer()
                            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(28)
            }
            .navigationTitle(upload.title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var spoken: String {
        if upload.findings.isEmpty { return "I didn't find anatomy words in this file." }
        return "Your file mentions: " + upload.findings.map { "\($0.term). \($0.meaning)" }.joined(separator: " ")
    }
}
