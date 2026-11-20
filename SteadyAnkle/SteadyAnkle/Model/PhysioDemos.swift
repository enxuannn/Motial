import Foundation

/// Real physiotherapists demonstrating each exercise, streamed with YouTube's official embedded player
/// (videos are public, embedding is enabled by their owners, nothing is copied into the app, the channel stays credited).
struct PhysioDemo: Equatable {
    let videoID: String
    let channel: String
    let title: String
}

enum PhysioDemos {
    static let byExercise: [String: PhysioDemo] = [
        "ankle_pumps": PhysioDemo(videoID: "KxfFzSOAT7g", channel: "Michigan Medicine", title: "Ankle Pumps"),
        "dawn_drive_cockpit": PhysioDemo(videoID: "KxfFzSOAT7g", channel: "Michigan Medicine", title: "Ankle Pumps"),
        "dawn_drive_seated": PhysioDemo(videoID: "KxfFzSOAT7g", channel: "Michigan Medicine", title: "Ankle Pumps"),
        "lantern_glide_seated": PhysioDemo(videoID: "KxfFzSOAT7g", channel: "Michigan Medicine", title: "Ankle Pumps"),
        "ankle_alphabet": PhysioDemo(videoID: "vHMJ0zgrsFU", channel: "Harvard Health Publishing", title: "The alphabet exercise for foot and ankle strength"),
        "seated_eversion": PhysioDemo(videoID: "xfrncpP5ONQ", channel: "AskDoctorJo", title: "Ankle eversion with resistive band"),
        "calf_raise": PhysioDemo(videoID: "4rgR6KtyHzI", channel: "NHS inform", title: "Standing double heel raises"),
        "dawn_drive": PhysioDemo(videoID: "4rgR6KtyHzI", channel: "NHS inform", title: "Standing double heel raises"),
        "lantern_glide": PhysioDemo(videoID: "4rgR6KtyHzI", channel: "NHS inform", title: "Standing double heel raises"),
        "knee_to_wall": PhysioDemo(videoID: "kbzYML05Vac", channel: "The Physio Channel", title: "Knee to wall dorsiflexion lunge"),
        "supported_sls": PhysioDemo(videoID: "ONfTUzBcd30", channel: "Advantage Physiotherapy", title: "Single leg balance (with support)"),
        "single_leg_stance": PhysioDemo(videoID: "FjwiVMhBhw0", channel: "Center For Total Back Care", title: "Single leg balance for ankle stability"),
        "sls_head_turns": PhysioDemo(videoID: "GDwI-XD8n-E", channel: "Symmetry Physical Therapy", title: "Single leg balance: head turns"),
        "sls_reach_catch": PhysioDemo(videoID: "z9d_tjae104", channel: "William Beaumont Army Medical Center", title: "Single leg balance ball toss"),
        "sl_mini_squat": PhysioDemo(videoID: "Eqw6w61Zsys", channel: "PhysioExercises", title: "Single leg mini squats"),
        "sl_calf_raise": PhysioDemo(videoID: "qPd73snQfUs", channel: "Hospital for Special Surgery", title: "Single-leg calf raise"),
        "stepping_stones": PhysioDemo(videoID: "jd8YGBCXkrY", channel: "Physiotutors", title: "Ankle sprain rehab: mobilisation, jumps, stability"),
        "rhythm_steps": PhysioDemo(videoID: "esVO96EkK_I", channel: "[P]rehab", title: "Return to sport exercises after an ankle sprain"),
        "hop_forward": PhysioDemo(videoID: "tawxi_JFcKA", channel: "INSYNC PHYSIO Vancouver", title: "One leg hops"),
        "side_hop": PhysioDemo(videoID: "r9dyrLsujJc", channel: "INSYNC PHYSIO Vancouver", title: "Lateral block hops"),
        "river_hops": PhysioDemo(videoID: "9RK_dNIAVM4", channel: "[P]rehab", title: "Ankle sprain: return to function and sport"),
    ]
}
