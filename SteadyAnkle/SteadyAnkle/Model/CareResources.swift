import Foundation

/// Where to get help. Shown in Learn, on the STOP screen and in Ask Steady's safety replies.
/// Singapore services first (the app is developed at NUS); everyone is reminded to use their own clinician
/// and their local emergency number when abroad.
struct CareResource: Identifiable {
    var id: String { name }
    let name: String
    let when: String
    let contact: String
    let url: String
    let symbol: String
    let urgent: Bool
}

enum CareResources {
    static let all: [CareResource] = [
        CareResource(name: "Singapore emergency ambulance (SCDF)", when: "Life-threatening emergencies only: you can't stand or walk at all after a fall, a head injury, the foot is cold, blue or deformed, or severe pain.",
                     contact: "Call 995", url: "https://scdf.gov.sg/home/about-us/information-on-ems/scdf-emergency-medical-services", symbol: "staroflife.fill", urgent: true),
        CareResource(name: "NurseFirst helpline (Singapore)", when: "Not sure where to go? Trained nurses advise you on the right care.",
                     contact: "Call 6262 6262", url: "https://www.nhghealth.com.sg/wh/clinical-care-services/nursefirst-helpline", symbol: "phone.fill", urgent: false),
        CareResource(name: "Your GP or polyclinic (HealthHub)", when: "Possible fracture (Ottawa rules), pain not improving after 1–2 weeks, or you need a physiotherapy referral.",
                     contact: "Book on HealthHub", url: "https://support.healthhub.sg/hc/en-us/articles/60045617129625-Book-and-Manage-Appointments-Easily", symbol: "cross.case.fill", urgent: false),
        CareResource(name: "Physiotherapy (e.g. SGH Physiotherapy)", when: "Recurrent sprains, 'giving way', a high ankle sprain, or help returning to sport. Ask your doctor for a referral.",
                     contact: "SGH appointments 6321 4377", url: "https://www.sgh.com.sg/our-specialties/physiotherapy", symbol: "figure.walk.motion", urgent: false),
    ]
    static let abroad = "Outside Singapore? Call your local emergency number, and contact your own doctor or physiotherapist."
    static let ownClinician = "Motial supports, and never replaces, your doctor or physiotherapist. Share your progress report with them from Progress."
}
