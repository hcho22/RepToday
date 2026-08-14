import Foundation

/// The user aggregate (US-A03): the person, their onboarding profile, their earned
/// phase, their entitlement, and their forgiving consistency stats.
///
/// These are plain `Codable` value types, deliberately decoupled from persistence -
/// the CoreData layer (US-A04) converts to/from `CDUser`, storing the nested
/// `profile`/`subscription`/`consistency` (and the v6 `why`/`duration`/`coldStart`) as
/// JSON-encoded `Data`. The engine and views work only with these structs.

// MARK: - User

/// A Rep Today user. `id` is the stable identity (the Sign in with Apple user
/// identifier once US-N01 lands); `phase` is computed by the `PhaseEvaluator` and is
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
    /// The user's stated motivation and its single allowed programming lever (US-D01).
    var why: Why = .empty
    /// The learned Default Duration surfaced on the Ready Screen (US-D01). A neutral
    /// placeholder here; onboarding (US-I01) seeds it from the user's answer.
    var duration: Duration = .seeded(minutes: 15)
    /// Cold-start state driving the cold-start strength lead and gentleness rails (US-D01). Fresh
    /// users start cold; the engine retires it after ~5 logged sessions (US-G04).
    var coldStart: ColdStart = .fresh
}

// MARK: - User.Why / Duration / ColdStart (v6, US-D01)

extension User {

    /// The user's stated motivation, captured once in onboarding (US-D01).
    ///
    /// `statement` is free text ("get on the floor with my grandkids"). `openingBias` is the
    /// **single** allowed *programming* effect of `why`: an optional pillar the engine may
    /// lean a session's opening toward. `why` never generates or otherwise overrides a
    /// session - the deterministic engine still assembles everything.
    struct Why: Codable, Equatable {
        /// Free-text motivation; empty for a skipped answer or a legacy (pre-v6) record.
        var statement: String
        /// The one lever `why` may move: an optional opening pillar bias.
        var openingBias: Pillar?

        /// A fresh/empty motivation: no statement, no bias. The documented default for a
        /// legacy user record that predates the `why` field.
        static let empty = Why(statement: "", openingBias: nil)
    }

    /// The user's learned session length (US-D01).
    ///
    /// `defaultMinutes` is what the Ready Screen offers and converges toward what the user
    /// actually completes; `onboardingSeedMinutes` is the one-time answer from onboarding;
    /// `completedDurationEWMA` is the exponentially-weighted average of completed durations
    /// the AI Programmer maintains (US-F04) and is nil until at least one session is logged.
    struct Duration: Codable, Equatable {
        /// Shown on the Ready Screen; set to the duration the user actually completes.
        var defaultMinutes: Int
        /// The duration answered once during onboarding; the starting seed for `defaultMinutes`.
        var onboardingSeedMinutes: Int
        /// EWMA of completed durations; nil until at least one session is logged.
        var completedDurationEWMA: Double?

        /// Seeds a fresh Duration from an onboarding answer, so `defaultMinutes ==
        /// onboardingSeedMinutes` and there is no completed-duration history yet. Also the
        /// documented default for a legacy record (seeded from `profile.typicalAvailableMinutes`).
        static func seeded(minutes: Int) -> Duration {
            Duration(defaultMinutes: minutes, onboardingSeedMinutes: minutes, completedDurationEWMA: nil)
        }
    }

    /// Cold-start state (US-D01). While `active`, the engine leads every day with strength
    /// (US-004, reversing the retired First-Week Contrast spread) and applies the capped Starting
    /// Difficulty and the Start Seed band/volume overrides
    /// (US-E04/US-G01/US-G02/US-O02); `sessionsLogged` increments per completed session and the
    /// engine flips `active` off after the handoff threshold (US-G04), after which staleness and
    /// Adaptive Overload drive sessions unassisted - with the single exception of
    /// `bandFloorAtHandoff` below, which keeps Step 5 from treating a chain the band hid as fresh.
    struct ColdStart: Codable, Equatable {
        /// Count of completed sessions during the cold-start window.
        var sessionsLogged: Int
        /// Whether cold-start overrides are still in effect.
        var active: Bool
        /// The Start Seed difficulty floor (US-O02) the cold-start week actually ran at, recorded
        /// once by `ColdStartHandoff` at the moment the band retires. `nil` means no banded cold
        /// start ever ran for this user - they are still inside the window, their record predates
        /// US-O02, or their contract carried the neutral floor - and Step 5 then withholds nothing.
        ///
        /// This is deliberately recorded rather than re-derived: the engine's `recentLogs` window is
        /// bounded (70 days), so the cold-start sessions that produced the band age out, and a
        /// derivation would silently start reporting a band the user never lived through. See
        /// `ColdStartOverride.withheldByStartSeed`.
        var bandFloorAtHandoff: Int?

        /// The contract's un-eased Start Seed floor *aim*, recorded beside `bandFloorAtHandoff` at the
        /// same moment. It exists so a `tooHard` rating that lands after the handoff - the retiring
        /// session is always rated on the completion screen, i.e. after the log is already written -
        /// can re-resolve `bandFloorAtHandoff` exactly from the aim and the now-rated cold-start
        /// sessions, instead of guessing at a step size. `nil` exactly when `bandFloorAtHandoff` is.
        var bandAimAtHandoff: Int?

        /// A brand-new user: no sessions logged yet, cold-start active, no band retired. The
        /// documented default for a legacy record that predates the `coldStart` field.
        static let fresh = ColdStart(sessionsLogged: 0, active: true)
    }
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
    /// "Do you sit 6+ hours most days?" - the desk-worker signal. Since US-M03 it *biases* bookend
    /// selection toward posture/hip openers (`SessionAssembly.postureHipLean`), never sizing any block:
    /// US-M01 retired the Movement Practice mobility block it used to size, so it is a pure ordering
    /// preference on the warm-up/cooldown pools and can never reintroduce a mobility middle block.
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

    /// The free tier - unlimited core workouts forever, no expiry. The default entitlement for a
    /// user who has never purchased, and what the real StoreKit service (US-N04) resolves to when
    /// there is no active premium entitlement.
    static let free = Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil)
}

/// The outcome of a paywall purchase attempt (US-N04), surfaced to the view model so it can tell a
/// resolved purchase (granted, or an unchanged entitlement after a silent user-cancel) apart from a
/// still-pending one awaiting external approval (e.g. Ask to Buy). Keeping the pending case distinct
/// lets the paywall reassure the user instead of leaving the Buy tap looking like nothing happened.
enum PurchaseOutcome: Equatable {
    /// The purchase flow finished: `subscription` is the resulting entitlement (premium on success,
    /// unchanged - typically `.free` - after a user-cancel).
    case resolved(Subscription)
    /// The purchase is deferred, awaiting external approval; the entitlement is unchanged for now and
    /// will be picked up out-of-band once approved.
    case pending
}
