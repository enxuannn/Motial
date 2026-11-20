import SwiftUI

/// Video calls with the person's own physio or doctor. Motial does not host calls: it opens the link the clinician
/// gave (Zoom, Microsoft Teams, FaceTime, or a phone number) at the moments the case needs it.
enum ClinicianCall {
    /// Turns what the person typed into something that opens a call: a meeting link as it is, a phone number or
    /// email as a FaceTime call.
    static func url(_ raw: String?) -> URL? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let lower = t.lowercased()
        for scheme in ["https://", "http://", "zoommtg://", "zoomus://", "msteams://", "facetime://", "facetime-audio://", "tel:"] where lower.hasPrefix(scheme) {
            return URL(string: t)
        }
        if lower.contains("zoom.us") || lower.contains("teams.microsoft") || lower.contains("teams.live") || lower.contains("meet.") {
            return URL(string: "https://" + t)
        }
        let digits = t.filter { $0.isNumber || $0 == "+" }
        if digits.count >= 6 { return URL(string: "facetime://" + digits) }
        if t.contains("@") { return URL(string: "facetime://" + t) }
        return nil
    }

    struct Reason { let text: String; let urgent: Bool }

    /// Why a call with the clinician is recommended now (the most important reason), or nil when the plan is on
    /// track. Each reason maps to the guidance used elsewhere in the app (triage, PAASS clearance, sprain type).
    @MainActor static func reason(_ model: AppModel) -> Reason? {
        guard let p = model.profile else { return nil }
        if case .seeClinicianFirst = model.triage {
            return Reason(text: "Your safety answers need a clinician's check before you exercise.", urgent: true)
        }
        if let c = model.state.checkIns.last, Calendar.current.isDateInToday(c.date),
           c.painRest >= 6 || (c.swelling == .worse && c.painRest >= 4) {
            return Reason(text: "Your ankle is more painful or swollen today. Let your physio take a look.", urgent: true)
        }
        if p.isHighAnkle && !p.clinicianGuided {
            return Reason(text: "High ankle sprains heal more slowly. Your physio should guide each step up.", urgent: false)
        }
        if p.type == .medial && !p.clinicianGuided {
            return Reason(text: "Inner ankle sprains can come with other injuries. A quick check is recommended.", urgent: false)
        }
        if p.type == .unsure && !p.clinicianGuided {
            return Reason(text: "A physio can confirm the type of sprain in a short call.", urgent: false)
        }
        if p.timeSince == .over6Weeks && model.latestPain >= 4 {
            return Reason(text: "Pain that lasts beyond 6 weeks should be assessed.", urgent: false)
        }
        if model.stage == .returnToActivity && !p.hopClearance {
            return Reason(text: "Ready for hops and sport drills? Your physio needs to clear jumping.", urgent: false)
        }
        if p.instabilityPattern && !p.clinicianGuided {
            return Reason(text: "Repeated sprains or 'giving way': a physio review is recommended.", urgent: false)
        }
        return nil
    }
}

/// Today card: shown only when the case calls for it. One line of why, one button to call.
struct ClinicianCallCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let reason: ClinicianCall.Reason
    @State private var adding = false

    var body: some View {
        let link = ClinicianCall.url(model.settings.clinicianLink)
        let who = model.settings.clinicianName ?? "your physio"
        HStack(spacing: Motial.Space.l) {
            Image(systemName: "video.fill").font(.title2)
                .foregroundStyle(reason.urgent ? .white : Motial.ink)
                .frame(width: 52, height: 52)
                .background(reason.urgent ? Motial.coral : Motial.pulse, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(reason.urgent ? "Talk to \(who) today" : "Check in with \(who)").font(.motialHeadline)
                Text(reason.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Motial.Space.m)
            if let link {
                Button { openURL(link) } label: { Label("Video call", systemImage: "video") }
                    .buttonStyle(.motialPrimaryCompact)
            } else {
                Button("Add clinician") { adding = true }.buttonStyle(.motialSecondary)
            }
        }
        .padding(Motial.Space.xl)
        .background(reason.urgent ? Motial.coral.opacity(0.14) : Motial.surface,
                    in: RoundedRectangle(cornerRadius: Motial.Radius.card, style: .continuous))
        .sheet(isPresented: $adding) { AddClinicianSheet().environment(model) }
    }
}

/// The two fields needed to call: a name and a link (or number). Shown from the Today card.
struct AddClinicianSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Motial.Space.l) {
            Text("YOUR CLINICIAN").font(.motialEyebrow).tracking(1.4).foregroundStyle(Motial.pulse)
            Text("Add your physio or doctor").font(.motialTitle)
            Text("Paste the video link they gave you (Zoom, Teams or FaceTime), or their phone number for FaceTime.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Name, e.g. Dr Tan", text: $name).textFieldStyle(.roundedBorder)
            TextField("Video link or phone number", text: $link).textFieldStyle(.roundedBorder).textContentType(.URL)
            if !link.isEmpty && ClinicianCall.url(link) == nil {
                Label("That doesn't look like a link or phone number yet.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Motial.caution)
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.motialSecondary)
                Spacer()
                Button("Save") {
                    var st = model.settings
                    st.clinicianName = name.isEmpty ? nil : name
                    st.clinicianLink = link.isEmpty ? nil : link
                    model.settings = st
                    dismiss()
                }
                .buttonStyle(.motialPrimaryCompact)
                .disabled(ClinicianCall.url(link) == nil)
            }
            Label("No clinician yet? In Singapore, NurseFirst 6262 6262 can advise where to go. Emergency: 995.", systemImage: "phone")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Motial.Space.xxl)
        .frame(width: 620)
        .onAppear { name = model.settings.clinicianName ?? ""; link = model.settings.clinicianLink ?? "" }
    }
}
