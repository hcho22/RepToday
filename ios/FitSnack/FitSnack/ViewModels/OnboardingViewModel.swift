import Foundation
import Observation

/// Drives the minimal v6 onboarding flow (US-I01).
///
/// Onboarding is minimal by design (the detailed flow is deferred to Phase 2): it collects the
/// handful of answers the deterministic engine needs, then ends by handing the app a fully-seeded
/// user so the Ready Screen (Epic J) can generate the first session with no picker to clear.
///
/// On `finish()` the view model:
/// 1. builds the `User` aggregate from the collected answers - seeding `duration` from the one
///    duration question (`defaultMinutes == onboardingSeedMinutes`) and starting `coldStart`
///    fresh (`active == true`, `sessionsLogged == 0`);
/// 2. saves that user through `UserServiceProtocol`; and
/// 3. seeds and persists the cold-start `SessionPolicy` through `SessionPolicyServiceProtocol`
///    (Starting Difficulty capped from `fitnessLevel`, First-Week Contrast forced on - US-G01),
///    so the engine's Step 0 overrides apply from session one.
///
/// It is an `@Observable` (Observation framework) view model per the project conventions; the
/// service work is `async throws` and surfaces failure through `errorMessage` without ever
/// trapping the flow.
@Observable
final class OnboardingViewModel {

    // MARK: - Steps

    /// The ordered onboarding steps. `CaseIterable` order is the flow order.
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case basics
        case fitnessLevel
        case why
        case lifestyle
        case duration

        var id: Int { rawValue }
    }

    // MARK: - Flow state

    /// The step currently on screen.
    private(set) var step: Step = .welcome

    /// True while the final save/seed work is in flight, so the finish button can show progress and
    /// avoid a double submit.
    private(set) var isFinishing = false

    /// A user-facing message set only when the final save/seed fails; `nil` in the happy path.
    private(set) var errorMessage: String?

    // MARK: - Collected answers

    var displayName: String = ""
    var age: Int = 35
    var sex: Sex = .female
    var heightCm: Double = 170
    var weightKg: Double = 70
    var fitnessLevel: FitnessLevel = .beginner
    var whyStatement: String = ""
    /// "Do you sit 6+ hours most days?" - biases short sessions toward mobility.
    var sitsLong: Bool = false
    /// The injuries the user selected, stored as engine tags (see `InjuryOption`).
    var selectedInjuries: Set<InjuryOption> = []
    /// The single duration answer; seeds both `defaultMinutes` and `onboardingSeedMinutes`.
    var durationMinutes: Int = 15

    // MARK: - Dependencies

    private let userService: any UserServiceProtocol
    private let sessionPolicyService: any SessionPolicyServiceProtocol
    /// Stable identity source (Sign in with Apple in production, a mock id in the MVP shell).
    private let userIdentifier: () -> String
    /// Injected clock, so `createdAt` stays testable and the view model has no hidden wall-clock read.
    private let now: () -> Date

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        userIdentifier: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.userIdentifier = userIdentifier
        self.now = now
    }

    // MARK: - Navigation

    var isFirstStep: Bool { step == Step.allCases.first }
    var isLastStep: Bool { step == Step.allCases.last }

    /// Whether the current step's required inputs are satisfied. The duration step is always ready
    /// (a value is preselected), so `finish()` is never gated behind an unanswered picker - the
    /// Ready Screen the flow ends on must not open onto a blocked Start (US-J01).
    var canAdvance: Bool {
        switch step {
        case .welcome, .fitnessLevel, .why, .lifestyle, .duration:
            return true
        case .basics:
            return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Finish

    /// Build, save, and seed the freshly-onboarded user, returning `true` on success so the caller
    /// can route to the Ready Screen. On failure it sets `errorMessage`, returns `false`, and leaves
    /// the flow in place so the user can retry.
    @discardableResult
    func finish() async -> Bool {
        guard !isFinishing else { return false }
        isFinishing = true
        errorMessage = nil
        defer { isFinishing = false }

        let user = buildUser()
        do {
            try await userService.save(user)
            // Seed the cold-start policy after the user is saved, so a warmed-up engine never reads
            // a contract for a user that failed to persist. The engine's Step 0 needs both.
            _ = try await sessionPolicyService.seedInitialPolicy(for: user)
            return true
        } catch {
            errorMessage = "We couldn't finish setting up. Please try again."
            return false
        }
    }

    /// Assemble the `User` aggregate from the collected answers. `primaryGoal` defaults to
    /// `.stayActive`: the v6 flow captures motivation through the free-text `why` instead, and
    /// `primaryGoal` only informs template tone, never the engine (see `PrimaryGoal`).
    func buildUser() -> User {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhy = whyStatement.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = UserProfile(
            age: age,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            fitnessLevel: fitnessLevel,
            primaryGoal: .stayActive,
            sitsLong: sitsLong,
            injuries: selectedInjuries.map(\.tag).sorted(),
            typicalAvailableMinutes: durationMinutes
        )

        return User(
            id: userIdentifier(),
            displayName: trimmedName,
            createdAt: now(),
            profile: profile,
            phase: .discipline,
            subscription: Subscription(tier: .free, provider: .apple, expiresAt: nil, trialEndsAt: nil),
            consistency: Consistency(
                weeklyGoal: ConsistencyScore.defaultWeeklyGoal,
                score: 0,
                workoutsThisWeek: 0,
                longestChain: 0,
                totalWorkoutsCompleted: 0,
                totalMinutesExercised: 0
            ),
            // `openingBias` stays nil in the minimal flow; the engine's cold-start rotation falls
            // back to `sitsLong ? .mobility : .strength` (US-E04) when no bias is stated.
            why: User.Why(statement: trimmedWhy, openingBias: nil),
            duration: .seeded(minutes: durationMinutes),
            coldStart: .fresh
        )
    }
}

// MARK: - Injury vocabulary

/// The closed set of injuries onboarding offers, each carrying the engine `tag` written into
/// `UserProfile.injuries`.
///
/// The raw `tag` values are chosen so every one normalizes onto a key the engine's
/// `InjuryContraindication` map recognizes (`ExercisePoolFilter` normalizes a tag by lower-casing,
/// stripping non-letters, and de-pluralizing). That reconciliation is required, not incidental: the
/// `InjuryContraindication` doc calls out that a tag which fails to normalize onto a key silently
/// disables injury protection. `OnboardingInjuryVocabularyTests` guards that every option here maps
/// to a non-empty contraindication set, so the gap can never reopen unnoticed.
enum InjuryOption: String, CaseIterable, Identifiable, Hashable {
    case knees
    case lowerBack
    case shoulders
    case wrists
    case ankles
    case hips

    var id: String { rawValue }

    /// The tag stored in `UserProfile.injuries` and read by `InjuryContraindication`.
    var tag: String {
        switch self {
        case .knees: return "knees"
        case .lowerBack: return "lower_back"
        case .shoulders: return "shoulders"
        case .wrists: return "wrists"
        case .ankles: return "ankles"
        case .hips: return "hips"
        }
    }

    /// The label shown in the onboarding chip.
    var label: String {
        switch self {
        case .knees: return "Knees"
        case .lowerBack: return "Lower back"
        case .shoulders: return "Shoulders"
        case .wrists: return "Wrists"
        case .ankles: return "Ankles"
        case .hips: return "Hips"
        }
    }
}
