import Foundation

/// User preferences that influence exercise selection during workout generation.
struct ExercisePreferences {
    /// Number of times each exercise has been skipped (exerciseId → count).
    var skipCounts: [String: Int]
    /// User star ratings for exercises (exerciseId → 1-5 rating).
    var ratings: [String: Int]
    /// Whether to restrict to apartment-friendly exercises only.
    var apartmentFriendly: Bool

    static let empty = ExercisePreferences(skipCounts: [:], ratings: [:], apartmentFriendly: false)
}
