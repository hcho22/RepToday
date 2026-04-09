import Foundation

/// Wraps an AI-generated text with metadata about its origin.
struct AITextResponse {
    let text: String
    let isFromCache: Bool
    let isFallback: Bool

    init(text: String, isFromCache: Bool = false, isFallback: Bool = false) {
        self.text = text
        self.isFromCache = isFromCache
        self.isFallback = isFallback
    }
}

protocol AIServiceProtocol {
    /// Post-workout summary (max ~100 tokens). Returns cached text if available for this workout ID.
    func generatePostWorkoutSummary(
        workout: Workout,
        userProfile: UserProfile,
        recentHistory: [Workout]
    ) async throws -> AITextResponse

    /// Weekly report (max ~300 tokens).
    func generateWeeklyReport(
        workouts: [Workout],
        userProfile: UserProfile,
        stats: GamificationStats
    ) async throws -> String

    /// Next-workout preview (max ~150 tokens).
    func generateNextWorkoutPreview(
        userProfile: UserProfile,
        recentHistory: [Workout],
        tomorrowsFocus: String
    ) async throws -> String
}
