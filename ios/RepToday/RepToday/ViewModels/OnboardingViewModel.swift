import AuthenticationServices
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

    // MARK: - Identity (US-N01)

    /// The Sign in with Apple identifier once the user has signed in, else `nil`. When present it
    /// keys the saved user record; when absent, `finish()` falls back to a locally-generated stable
    /// identifier, so sign-in is never a gate to the first session.
    private(set) var signedInIdentifier: String?

    /// True while the (optional, non-gating) Sign in with Apple sheet is in flight.
    private(set) var isSigningIn = false

    // MARK: - Collected answers

    var displayName: String = ""
    var age: Int = 35
    var sex: Sex = .female
    /// Height, collected in the units a US user thinks in (US-O04). Defaults sit near the US adult
    /// median so the control opens somewhere plausible rather than at the end of its range.
    var heightFeet: Int = 5
    var heightInches: Int = 8
    /// Weight in whole pounds (US-O04), likewise near the US adult median.
    var weightPounds: Int = 175
    var fitnessLevel: FitnessLevel = .beginner
    var whyStatement: String = ""
    /// "Do you sit 6+ hours most days?" - biases short sessions toward mobility.
    var sitsLong: Bool = false
    /// The injuries the user selected, stored as engine tags (see `InjuryOption`).
    var selectedInjuries: Set<InjuryOption> = []
    /// The single duration answer; seeds both `defaultMinutes` and `onboardingSeedMinutes`.
    var durationMinutes: Int = 15

    // MARK: - Imperial <-> metric boundary (US-O04)

    /// The height answer as one number, so a single control can set both parts and the feet/inches
    /// split stays normalized (`5 ft 12 in` is unreachable). Reading and writing both go through
    /// `heightFeet`/`heightInches`, which remain the collected answers.
    var heightTotalInches: Int {
        get { heightFeet * UnitConversion.inchesPerFoot + heightInches }
        set {
            let split = UnitConversion.feetAndInches(totalInches: newValue)
            heightFeet = split.feet
            heightInches = split.inches
        }
    }

    /// The imperial height in the metric unit `UserProfile` persists. Derived, never stored: the
    /// user's answer has exactly one representation, so the two can never drift apart.
    var heightCm: Double {
        UnitConversion.centimeters(feet: heightFeet, inches: heightInches)
    }

    /// The imperial weight in the metric unit `UserProfile` persists - and the unit the HealthKit
    /// energy estimate (`MET x weightKg x hours`) reads, which is why the conversion happens here and
    /// not somewhere downstream.
    var weightKg: Double {
        UnitConversion.kilograms(fromPounds: Double(weightPounds))
    }

    // MARK: - Dependencies

    private let userService: any UserServiceProtocol
    private let sessionPolicyService: any SessionPolicyServiceProtocol
    /// Sign in with Apple identity (US-N01). Optional so tests and previews that do not exercise
    /// sign-in construct the view model without it; when absent, identity falls back to
    /// `userIdentifier` below.
    private let authService: (any AuthServiceProtocol)?
    /// Anonymous product telemetry sink (US-T08). Optional exactly like `authService`, so previews
    /// and tests that do not exercise the funnel construct the view model unchanged; when absent the
    /// two onboarding-funnel emissions are simply skipped. Emissions go through it **unconditionally**
    /// - consent (US-T06) is enforced inside the sink, so this view model never re-checks the opt-out
    /// flag (a second gate could disagree with the first).
    private let analytics: (any AnalyticsServiceProtocol)?
    /// The local fallback identity source, used only when the user has not signed in with Apple, so
    /// the offline-first core loop always has a stable key without requiring an iCloud account.
    private let userIdentifier: () -> String
    /// Injected clock, so `createdAt` stays testable and the view model has no hidden wall-clock read.
    /// It also anchors the onboarding-funnel `elapsed_seconds` (US-T08), so that measurement is
    /// deterministic under a test clock rather than a raw `Date()` read.
    private let now: () -> Date

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        authService: (any AuthServiceProtocol)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        userIdentifier: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.authService = authService
        self.analytics = analytics
        self.userIdentifier = userIdentifier
        self.now = now
    }

    // MARK: - Onboarding funnel telemetry (US-T08)

    /// Guards `onboarding_started` to exactly one emission per view-model lifetime, so a re-`onAppear`
    /// within the same flow does not double-fire. This is not persisted across launches: the funnel
    /// counts distinct installs and the backend dedups by `installId`, so emitting once per
    /// presentation is correct.
    private var didEmitOnboardingStarted = false

    /// The instant `onboarding_started` was emitted, captured off the injected clock. It anchors the
    /// `elapsed_seconds` `onboarding_completed` carries. `nil` until the first `onboardingStarted()`
    /// call, so a `finish()` that somehow ran without one omits the elapsed anchor cleanly rather than
    /// fabricating a start.
    private var onboardingStartInstant: Date?

    /// Emits `onboarding_started` (no properties) on the first onboarding screen's appearance, exactly
    /// once per flow, and records the start instant that anchors `elapsed_seconds`. Fire-and-forget:
    /// the sink returns immediately and swallows any failure, so this never gates onboarding.
    func onboardingStarted() async {
        guard !didEmitOnboardingStarted else { return }
        didEmitOnboardingStarted = true
        onboardingStartInstant = now()
        await analytics?.record(AnalyticsEvent(name: .onboardingStarted, timestampMs: timestampMs()))
    }

    /// The current millisecond client timestamp off the injected clock - the same encoding
    /// `AnalyticsEvent` carries everywhere, with no raw `Date()` read.
    private func timestampMs() -> Int {
        Int(now().timeIntervalSince1970 * 1000)
    }

    // MARK: - Sign in with Apple (US-N01)

    /// Whether a sign-in affordance should be offered - only when an auth service is wired and the
    /// user has not already signed in during this flow.
    var canSignInWithApple: Bool { authService != nil && signedInIdentifier == nil }

    /// Runs the optional Sign in with Apple ceremony and, on success, records the stable identifier
    /// so `finish()` keys the user record by it. Any failure (offline, canceled, missing entitlement)
    /// is intentionally swallowed: sign-in must never gate the first session, so the flow silently
    /// falls back to a locally-generated identifier.
    func signInWithApple() async {
        guard let authService, !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        signedInIdentifier = try? await authService.signInWithApple()
    }

    /// Handles the official `SignInWithAppleButton`'s completion. A thin extraction shim: it pulls the
    /// stable identifier off a successful Apple ID credential and hands it to `completeSignIn`. Any
    /// failure (canceled, offline, missing entitlement) or a non-Apple-ID credential is intentionally
    /// swallowed - sign-in must never gate the first session.
    @MainActor
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard
            case .success(let authorization) = result,
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else { return }
        let identifier = credential.user
        Task { await completeSignIn(identifier: identifier) }
    }

    /// Records an externally-obtained Sign in with Apple identifier (from the button's completion) so
    /// `finish()` keys the user by it, persisting it best-effort through the auth service. The persist
    /// failure is swallowed for the same non-gating reason as `signInWithApple()`.
    func completeSignIn(identifier: String) async {
        try? await authService?.completeSignIn(identifier: identifier)
        signedInIdentifier = identifier
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

        let user = buildUser(identifier: await resolvedIdentifier())
        do {
            try await userService.save(user)
            // Seed the cold-start policy after the user is saved, so a warmed-up engine never reads
            // a contract for a user that failed to persist. The engine's Step 0 needs both.
            _ = try await sessionPolicyService.seedInitialPolicy(for: user)
            // US-T08: `onboarding_completed` fires only here, on the success branch that also triggers
            // `onComplete` - never on the failure branch below. `elapsed_seconds` is whole seconds from
            // the `onboarding_started` instant to now, off the injected clock, clamped at 0 defensively.
            // Fire-and-forget through the sink, after the durable work, so telemetry never gates the
            // save/seed. If no start instant was recorded (the emission site was never reached), elapsed
            // is treated as 0 rather than fabricating a start.
            let elapsedSeconds = onboardingStartInstant.map { max(0, Int(now().timeIntervalSince($0))) } ?? 0
            await analytics?.record(
                AnalyticsEvent(
                    name: .onboardingCompleted,
                    timestampMs: timestampMs(),
                    properties: ["elapsed_seconds": .int(elapsedSeconds)]
                )
            )
            return true
        } catch {
            errorMessage = "We couldn't finish setting up. Please try again."
            return false
        }
    }

    /// The identity that keys the saved user record: the Sign in with Apple identifier (whether it
    /// arrived via `signInWithApple()` this session or was persisted from a prior sign-in), else the
    /// local fallback. A best-effort local read of the auth store - it never calls Apple - so it
    /// resolves instantly and offline and never blocks `finish()`.
    private func resolvedIdentifier() async -> String {
        if let signedInIdentifier { return signedInIdentifier }
        if let authService, let existing = try? await authService.currentUserIdentifier() {
            return existing
        }
        return userIdentifier()
    }

    /// Assemble the `User` aggregate from the collected answers, keyed by `userIdentifier()` (the
    /// local fallback). `finish()` uses `buildUser(identifier:)` with the resolved Sign in with Apple
    /// identity; this convenience keeps the synchronous, identity-agnostic build available.
    func buildUser() -> User {
        buildUser(identifier: userIdentifier())
    }

    /// Assemble the `User` aggregate from the collected answers, keyed by the given identifier.
    /// `primaryGoal` defaults to `.stayActive`: the v6 flow captures motivation through the free-text
    /// `why` instead, and `primaryGoal` only informs template tone, never the engine (see `PrimaryGoal`).
    func buildUser(identifier: String) -> User {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhy = whyStatement.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = UserProfile(
            age: age,
            sex: sex,
            // The imperial -> metric boundary (US-O04): the UI collects feet/inches and pounds, the
            // persisted profile is metric, and everything downstream - CloudKit, the HealthKit
            // energy estimate - only ever sees cm/kg.
            heightCm: heightCm,
            weightKg: weightKg,
            fitnessLevel: fitnessLevel,
            primaryGoal: .stayActive,
            sitsLong: sitsLong,
            injuries: selectedInjuries.map(\.tag).sorted(),
            typicalAvailableMinutes: durationMinutes
        )

        return User(
            id: identifier,
            displayName: trimmedName,
            createdAt: now(),
            profile: profile,
            phase: .discipline,
            subscription: .free,
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
