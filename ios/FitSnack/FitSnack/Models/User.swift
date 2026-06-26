import Foundation

/// The user aggregate (US-A03): the person, their onboarding profile, their earned
/// phase, their entitlement, and their forgiving consistency stats.
///
/// These are plain `Codable` value types, deliberately decoupled from persistence -
/// the CoreData layer (US-A04) converts to/from `CDUser`, storing the nested
/// `profile`/`subscription`/`consistency` as JSON-encoded `Data`. The engine and
/// views work only with these structs.

// MARK: - User

/// A FitSnack user. `id` is the stable identity (the Sign in with Apple user
/// identifier once US-J01 lands); `phase` is computed by the `PhaseEvaluator` and is
/// never user-selectable.
struct User: Codable, Equatable, Identifiable {
    /// Stable identity - the Sign in with Apple user id string in production.
    var id: String
    var displayName: String
    var createdAt: Date
    var profile: UserProfile
    /// Earned, deterministic phase. All MVP users resolve to `.discipline`.
    var phase: Phase
    var subscription: Subscription
    var consistency: Consistency
}

// MARK: - UserProfile

/// The onboarding answers that personalize session generation. Captured once in the
/// minimal onboarding flow (US-E01) and editable later.
struct UserProfile: Codable, Equatable {
    var age: Int
    var sex: Sex
    var heightCm: Double
    var weightKg: Double
    var fitnessLevel: FitnessLevel
    var primaryGoal: PrimaryGoal
    /// "Do you sit 6+ hours most days?" - biases short sessions toward Movement Practice.
    var sitsLong: Bool
    /// Injury tags (e.g. `"lower_back"`, `"knees"`) used to filter the exercise pool.
    var injuries: [String]
    /// The duration the user usually has, used to auto-generate today's session.
    var typicalAvailableMinutes: Int
}

// MARK: - Consistency

/// The forgiving, rolling measure of showing up (US-D01). There is no streak to break
/// and no XP - a single miss dents `score` but never zeroes it, and a 5-minute session
/// counts as a full show-up. `longestChain` is surfaced as earned pride, never a threat.
struct Consistency: Codable, Equatable {
    /// Target sessions per week (default 3).
    var weeklyGoal: Int
    /// Rolling 0-100 weighted average of weekly adherence.
    var score: Double
    var workoutsThisWeek: Int
    /// Longest run of consecutive on-goal weeks ever achieved.
    var longestChain: Int
    var totalWorkoutsCompleted: Int
    var totalMinutesExercised: Int
}

// MARK: - Subscription

/// The user's entitlement. The core loop is free and unlimited forever; `premium`
/// only unlocks the depth layer. Dates are nil when not applicable (e.g. a free user
/// has no `expiresAt`).
struct Subscription: Codable, Equatable {
    var tier: SubscriptionTier
    var provider: SubscriptionProvider
    var expiresAt: Date?
    var trialEndsAt: Date?
}
