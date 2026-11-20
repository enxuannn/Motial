import Foundation
import Vision
import UIKit
import PDFKit

/// An X-ray image or a medical report the person adds so they can *understand* it next to the 3D ankle.
/// Educational only: Steady never reads images to diagnose. Text in reports is read on-device (Vision OCR)
/// to find anatomy terms, which are explained in plain language and highlighted on the 3D model.
struct MedicalUpload: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case xray, report }
    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    var fileName: String            // stored in Documents/Uploads
    var text: String = ""           // recognised text (reports, or text burned into an X-ray image)
    var findings: [ReportFinding] = []
}

struct ReportFinding: Codable, Identifiable, Equatable, Hashable {
    var id: String { term }
    let term: String                // the word or phrase found
    let meaning: String             // plain-language explanation
    let structure: String?          // AnatomyInfo / ligament key to highlight in 3D
    let caution: Bool               // something a clinician should guide (e.g. fracture, complete tear)
}

enum ReportGlossary {
    struct Entry { let patterns: [String]; let term: String; let meaning: String; let structure: String?; let caution: Bool }
    static let entries: [Entry] = [
        Entry(patterns: ["atfl", "anterior talofibular"], term: "ATFL (anterior talofibular ligament)",
              meaning: "The outer-ankle ligament injured in most sprains. It runs from the fibula to the talus at the front of the ankle.", structure: "ATFL", caution: false),
        Entry(patterns: ["cfl", "calcaneofibular"], term: "CFL (calcaneofibular ligament)",
              meaning: "The outer ligament from the fibula down to the heel bone, often involved in bigger sprains together with the ATFL.", structure: "CFL", caution: false),
        Entry(patterns: ["ptfl", "posterior talofibular"], term: "PTFL (posterior talofibular ligament)",
              meaning: "The deepest and strongest outer ligament, rarely torn.", structure: "PTFL", caution: false),
        Entry(patterns: ["aitfl", "syndesmo", "high ankle", "tibiofibular"], term: "Syndesmosis / high ankle sprain",
              meaning: "The ligaments that hold the shin bones together above the ankle. These injuries recover more slowly and need physiotherapist guidance.", structure: "AITFL", caution: true),
        Entry(patterns: ["deltoid", "medial ligament"], term: "Deltoid ligament",
              meaning: "The strong fan of ligaments on the inner ankle.", structure: "Deltoid_TN", caution: false),
        Entry(patterns: ["fibula", "lateral malleol"], term: "Fibula / lateral malleolus",
              meaning: "The thin outer leg bone; its tip is the outer ankle bone.", structure: "fibula", caution: false),
        Entry(patterns: ["tibia", "medial malleol", "plafond"], term: "Tibia / medial malleolus",
              meaning: "The shin bone; its lower end forms the inner ankle bone and the roof of the ankle joint.", structure: "tibia", caution: false),
        Entry(patterns: ["talus", "talar dome", "osteochondral", "ocd", "ocl"], term: "Talus / talar dome",
              meaning: "The bone that sits in the ankle joint. Reports sometimes mention cartilage (osteochondral) injury here, which needs clinician guidance.", structure: "talus", caution: false),
        Entry(patterns: ["calcane"], term: "Calcaneus (heel bone)", meaning: "The heel bone.", structure: "calcaneus", caution: false),
        Entry(patterns: ["navicular"], term: "Navicular", meaning: "The inner arch bone of the midfoot.", structure: "navicular", caution: false),
        Entry(patterns: ["fifth metatarsal", "5th metatarsal", "base of the 5th", "jones"], term: "5th metatarsal",
              meaning: "The long bone on the outer edge of the foot. Its base can break during a sprain.", structure: "metatarsal_5", caution: false),
        Entry(patterns: ["peroneal", "fibularis"], term: "Peroneal (fibularis) tendons",
              meaning: "The tendons behind the outer ankle bone that protect against rolling. Strengthening them is part of your plan.", structure: "fibularis_longus", caution: false),
        Entry(patterns: ["achilles"], term: "Achilles tendon", meaning: "Connects the calf muscles to the heel.", structure: "achilles_tendon", caution: false),
        Entry(patterns: ["grade i ", "grade 1", "mild sprain"], term: "Grade 1 sprain",
              meaning: "The ligament is stretched with little or no tearing. Most people recover well with exercise.", structure: nil, caution: false),
        Entry(patterns: ["grade ii", "grade 2", "partial tear", "partial thickness"], term: "Grade 2 / partial tear",
              meaning: "Part of the ligament is torn. Recovery usually takes several weeks with progressive exercise.", structure: nil, caution: false),
        Entry(patterns: ["grade iii", "grade 3", "complete tear", "full thickness", "rupture"], term: "Grade 3 / complete tear",
              meaning: "The ligament is fully torn. Exercise is still the main treatment, but a clinician should guide your progression.", structure: nil, caution: true),
        Entry(patterns: ["fracture", "avulsion", "# "], term: "Fracture / avulsion",
              meaning: "A break in a bone, or a small piece of bone pulled off by a ligament. Follow your clinician's plan before loading the ankle.", structure: nil, caution: true),
        Entry(patterns: ["effusion", "swelling", "oedema", "edema", "bone bruise", "bone marrow"], term: "Swelling / effusion / bone bruise",
              meaning: "Fluid or bruising in or around the joint. It is common after a sprain and settles over weeks.", structure: nil, caution: false),
        Entry(patterns: ["instability", "laxity"], term: "Instability / laxity",
              meaning: "The ankle moves more than it should or gives way. Balance training is the most important treatment.", structure: nil, caution: false),
    ]

    static func findings(in text: String) -> [ReportFinding] {
        let t = " " + text.lowercased().replacingOccurrences(of: "\n", with: " ") + " "
        var out: [ReportFinding] = []
        for e in entries where e.patterns.contains(where: { t.contains($0) }) {
            out.append(ReportFinding(term: e.term, meaning: e.meaning, structure: e.structure, caution: e.caution))
        }
        return out
    }
}

enum ReportReader {
    static var folder: URL {
        let u = AppModel.documents.appendingPathComponent("Uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Copies a picked file into the app, reads any text on it, and builds the upload record.
    static func importFile(_ src: URL) async -> MedicalUpload? {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let isPDF = src.pathExtension.lowercased() == "pdf"
        let name = UUID().uuidString + "." + (isPDF ? "pdf" : "png")
        let dst = folder.appendingPathComponent(name)
        var image: UIImage?
        if isPDF {
            guard (try? FileManager.default.copyItem(at: src, to: dst)) != nil else { return nil }
            image = pdfFirstPage(dst)
        } else {
            guard let data = try? Data(contentsOf: src), let img = UIImage(data: data), let png = img.pngData() else { return nil }
            try? png.write(to: dst, options: .completeFileProtection)
            image = img
        }
        var text = ""
        if isPDF, let doc = PDFDocument(url: dst), let s = doc.string, !s.isEmpty { text = s }
        if text.isEmpty, let img = image { text = await recogniseText(img) }
        let findings = ReportGlossary.findings(in: text)
        let looksLikeReport = isPDF || text.split(separator: " ").count > 25
        return MedicalUpload(kind: looksLikeReport ? .report : .xray,
                             title: src.deletingPathExtension().lastPathComponent,
                             fileName: name, text: text, findings: findings)
    }

    static func image(for u: MedicalUpload) -> UIImage? {
        let url = folder.appendingPathComponent(u.fileName)
        if url.pathExtension == "pdf" { return pdfFirstPage(url) }
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(_ u: MedicalUpload) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(u.fileName))
    }

    private static func pdfFirstPage(_ url: URL) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 1400, height: 1800), for: .mediaBox)
    }

    /// On-device text recognition (Vision). Nothing leaves the device.
    static func recogniseText(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cg).perform([req])
                let lines = req.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
