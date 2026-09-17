import Foundation

/// The approved, non-identifying native QA fixtures, shared verbatim with physical-iPhone QA.
/// These summaries are not workout prescriptions or actual user history. Never persist them as logs.
enum CoachSyntheticFixtures {
    static let whyContext = CoachContextBundle(
        phase: "discipline", requestedMinutes: 20,
        chainPositions: [.init(pattern: "squat", currentExercise: "Bodyweight Squat", tier: 3, chainLength: 5, hasNextTier: true)],
        recentPatterns: ["push", "hinge", "core"],
        consistency: .init(currentScore: 63, direction: .rising), strengthJourney: []
    )
    static let pistolContext = CoachContextBundle(
        phase: "strength", requestedMinutes: 15,
        chainPositions: [.init(pattern: "squat", currentExercise: "Assisted Pistol Squat", tier: 6, chainLength: 7, hasNextTier: true)],
        recentPatterns: ["squat", "push"],
        consistency: .init(currentScore: 88, direction: .steady),
        strengthJourney: [.init(pattern: "squat", trend: "flat", weeksAtCurrentTier: 3, hasAdvanced: true)]
    )
    static let whyPrompt = "Why did I get squats today? Refer to the supplied phase, squat frontier and recent patterns. Explain what the summary supports and what you cannot know about today's exact session; do not invent or change a workout."
    static let pistolPrompt = "How do I do a pistol squat? Relate safe form guidance to my supplied current squat frontier and earned phase, without prescribing or changing a workout."


    enum Selection: String, CaseIterable {
        case whySquats = "why-squats", pistolForm = "pistol-form"
        var title: String { self == .whySquats ? "Why squats" : "Pistol-squat form" }
        var prompt: String { self == .whySquats ? CoachSyntheticFixtures.whyPrompt : CoachSyntheticFixtures.pistolPrompt }
        var context: CoachContextBundle { self == .whySquats ? CoachSyntheticFixtures.whyContext : CoachSyntheticFixtures.pistolContext }
    }
}
