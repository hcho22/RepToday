import Foundation
import Observation

/// Drives the minimal v6 onboarding flow (US-I01).
///
/// Onboarding is minimal by design (the detailed flow is deferred to Phase 2): it collects the
/// handful of answers the deterministic engine needs, then ends by handing the app a fully-seeded
/// user so the Ready Screen (Epic J) can generate the first session with no picker to clear.
///
/// The last step, "Save your plan" (M3, US-AU02, decision 23), asks the user to sign in to their Rep
/// Today account; onboarding cannot finish without it. Once they have signed in,
/// `completeSignIn(as:)` either brings back the plan the account already holds - someone signing in on
/// a new phone - or creates the new user through `finish()`.
///
/// Someone who already has an account can go straight there from the Welcome step
/// (`goToSignIn()`) - after signing out, or on a new phone or a reinstall. An account with a saved plan
/// brings it back with no questions; one without continues into the questions and finishes from the
/// last of them (`finishesSignedIn`), so a brand-new account still onboards.
///
/// On `finish()` the view model:
/// 1. builds the `User` aggregate from the collected answers - seeding `duration` from the one
///    duration question (`defaultMinutes == onboardingSeedMinutes`) and starting `coldStart`
///    fresh (`active == true`, `sessionsLogged == 0`);
/// 2. saves that user through `UserServiceProtocol`; and
/// 3. seeds and persists the cold-start `SessionPolicy` through `SessionPolicyServiceProtocol`
///    (Starting Difficulty capped from `fitnessLevel` - US-G01, cold-start strength lead forced on - US-004),
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
        case focusAreas
        case why
        case lifestyle
        case duration
        /// Sign in so the plan is saved to the account (US-AU02). Required to finish.
        case saveYourPlan

        var id: Int { rawValue }
    }

    /// How a signed-in onboarding ended.
    enum Completion: Equatable {
        /// A new plan was created from the answers.
        case created
        /// The account already held a plan, and it was brought back to this phone.
        case restored
        /// The account holds no plan and the questions have not been answered yet: the flow continues
        /// into them, signed in, and finishes from the last one.
        case needsAnswers
    }

    /// Why onboarding could not finish after signing in. Nothing was saved; the user can try again.
    enum CompletionError: Error, Equatable {
        /// The account could not be reached to check for a plan it already holds.
        case accountUnreachable
        /// Saving the new plan on the phone failed.
        case saveFailed
    }

    // MARK: - Flow state

    /// The step currently on screen.
    private(set) var step: Step = .welcome

    /// True while the final save/seed work is in flight, so the finish button can show progress and
    /// avoid a double submit.
    private(set) var isFinishing = false

    /// A user-facing message set only when the final save/seed fails; `nil` in the happy path.
    private(set) var errorMessage: String?

    /// Whether "Save your plan" was reached from the Welcome step's sign-in link rather than through
    /// the questions, so its Back returns to Welcome and an account with no plan goes on to the
    /// questions rather than being created from unanswered defaults.
    private(set) var isSigningInFromWelcome = false

    /// The account signed in to from the Welcome step that holds no plan yet. Set while the user answers
    /// the questions; the flow then finishes from the last of them instead of asking to sign in again.
    private(set) var signedInIdentity: AccountIdentity?

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
    /// The body parts the user wants to improve (decision 20). Optional: none is a complete answer.
    var selectedFocusAreas: Set<FocusArea> = []
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
    /// Brings back the plan an account already holds (`SyncEngine.restoreFromAccount`), or `nil` when
    /// this build has no account backend, in which case every sign-in creates a new plan.
    private let accountRestorer: (any AccountRestoring)?
    /// Anonymous product telemetry sink (US-T08). Optional, so previews
    /// and tests that do not exercise the funnel construct the view model unchanged; when absent the
    /// two onboarding-funnel emissions are simply skipped. Emissions go through it **unconditionally**
    /// - consent (US-T06) is enforced inside the sink, so this view model never re-checks the opt-out
    /// flag (a second gate could disagree with the first).
    private let analytics: (any AnalyticsServiceProtocol)?
    /// Keys a new user record. A local random id: the account owns the data on the server, so the
    /// record key never has to change when the user signs in on another phone.
    private let userIdentifier: () -> String
    /// Injected clock, so `createdAt` stays testable and the view model has no hidden wall-clock read.
    /// It also anchors the onboarding-funnel `elapsed_seconds` (US-T08), so that measurement is
    /// deterministic under a test clock rather than a raw `Date()` read.
    private let now: () -> Date

    init(
        userService: any UserServiceProtocol,
        sessionPolicyService: any SessionPolicyServiceProtocol,
        accountRestorer: (any AccountRestoring)? = nil,
        analytics: (any AnalyticsServiceProtocol)? = nil,
        userIdentifier: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = { Date() }
    ) {
        self.userService = userService
        self.sessionPolicyService = sessionPolicyService
        self.accountRestorer = accountRestorer
        self.analytics = analytics
        self.userIdentifier = userIdentifier
        self.now = now
    }

    // MARK: - Onboarding funnel telemetry (US-T08)

    /// Guards `onboarding_started` to exactly one emission per view-model lifetime, so a re-`onAppear`
    /// within the same flow does not double-fire. This is not persisted across launches: each new
    /// presentation is a new funnel attempt, while transport retries of one accepted emission are
    /// deduplicated separately by its stable `eventId`.
    private var didEmitOnboardingStarted = false

    /// The instant `onboarding_started` was emitted, captured off the injected clock. It anchors the
    /// `elapsed_seconds` `onboarding_completed` carries. `nil` until the first `onboardingStarted()`
    /// call, so a `finish()` that somehow ran without one omits the elapsed anchor cleanly rather than
    /// fabricating a start.
    private var onboardingStartInstant: Date?

    /// Emits `onboarding_started` (no properties) on the first onboarding screen's appearance, exactly
    /// once per flow, and records the start instant that anchors `elapsed_seconds`. The sink performs
    /// only its bounded synchronous acceptance and swallows failures; storage and delivery stay off this path.
    func onboardingStarted() {
        guard !didEmitOnboardingStarted else { return }
        didEmitOnboardingStarted = true
        onboardingStartInstant = now()
        analytics?.record(AnalyticsEvent(name: .onboardingStarted, timestampMs: timestampMs()))
    }

    /// The current millisecond client timestamp off the injected clock - the same encoding
    /// `AnalyticsEvent` carries everywhere, with no raw `Date()` read.
    private func timestampMs() -> Int {
        Int(now().timeIntervalSince1970 * 1000)
    }

    // MARK: - Navigation

    var isFirstStep: Bool { step == Step.allCases.first }
    var isLastStep: Bool { step == Step.allCases.last }

    /// Whether the step on screen finishes onboarding for an account already signed in: the last
    /// question, once the Welcome step's sign-in found no plan.
    var finishesSignedIn: Bool { signedInIdentity != nil && step == .duration }

    /// The steps this flow walks, for the progress bar: without "Save your plan" once already signed in.
    var progressSteps: [Step] {
        signedInIdentity == nil ? Step.allCases : Step.allCases.filter { $0 != .saveYourPlan }
    }

    /// Whether the Welcome step offers signing in to an existing account. Not once signed in.
    var offersSignInFromWelcome: Bool { step == .welcome && signedInIdentity == nil }

    /// Whether the current step's required inputs are satisfied. The duration step is always ready
    /// (a value is preselected), so the flow is never gated behind an unanswered picker - the Ready
    /// Screen the flow ends on must not open onto a blocked Start (US-J01). "Save your plan" advances
    /// only by signing in, so it has no Continue.
    var canAdvance: Bool {
        switch step {
        case .welcome, .fitnessLevel, .focusAreas, .why, .lifestyle, .duration:
            return true
        case .basics:
            return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .saveYourPlan:
            return false
        }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        if step == .saveYourPlan && isSigningInFromWelcome {
            isSigningInFromWelcome = false
            step = .welcome
            return
        }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// "Already have an account? Sign in" on the Welcome step: straight to the sign-in on "Save your
    /// plan", skipping the questions.
    func goToSignIn() {
        guard offersSignInFromWelcome else { return }
        isSigningInFromWelcome = true
        step = .saveYourPlan
    }

    // MARK: - Finish

    /// Finishes onboarding for the account the user just signed in to (US-AU02). An account that
    /// already holds a plan - the same person on a new phone - gets it back, history and all, and the
    /// answers given here are not used; otherwise the answers become the new plan (`finish()`).
    ///
    /// The account is checked before anything is written, so a returning user's plan can never be
    /// overwritten by a fresh one. If the account cannot be reached, nothing is saved and the user can
    /// try again. An account that is still being deleted is refused as such
    /// (`SyncRemoteError.accountDeleting`), so the user can wait or use a different sign-in. Signed in
    /// from the Welcome step, an account with no plan continues into the questions (`.needsAnswers`)
    /// rather than getting a plan built from answers never given.
    func completeSignIn(as identity: AccountIdentity) async throws -> Completion {
        if let accountRestorer {
            let restoredTypes: Set<SyncRecordType>
            do {
                restoredTypes = try await accountRestorer.restoreFromAccount()
            } catch SyncRemoteError.accountDeleting {
                throw SyncRemoteError.accountDeleting
            } catch {
                throw CompletionError.accountUnreachable
            }
            if restoredTypes.contains(.profile), (try? await userService.currentUser()) != nil {
                recordOnboardingCompleted()
                return .restored
            }
        }
        if isSigningInFromWelcome {
            isSigningInFromWelcome = false
            signedInIdentity = identity
            step = .basics
            return .needsAnswers
        }
        guard await finish() else { throw CompletionError.saveFailed }
        return .created
    }

    /// Build, save, and seed the freshly-onboarded user, returning `true` on success so the caller
    /// can route to the Ready Screen. On failure it sets `errorMessage`, returns `false`, and leaves
    /// the flow in place so the user can retry.
    @discardableResult
    func finish() async -> Bool {
        guard !isFinishing else { return false }
        isFinishing = true
        errorMessage = nil
        defer { isFinishing = false }

        let user = buildUser(identifier: userIdentifier())
        do {
            try await userService.save(user)
            // Seed the cold-start policy after the user is saved, so a warmed-up engine never reads
            // a contract for a user that failed to persist. The engine's Step 0 needs both.
            _ = try await sessionPolicyService.seedInitialPolicy(for: user)
            // US-T08: `onboarding_completed` fires only on success - never on the failure branch below.
            recordOnboardingCompleted()
            return true
        } catch {
            errorMessage = "We couldn't finish setting up. Please try again."
            return false
        }
    }

    /// The plan was saved but the signed-in account could not be linked to it, so the flow stays put.
    func reportFinishingFailed() {
        errorMessage = "We couldn't finish setting up. Please try again."
    }

    /// `onboarding_completed` (US-T08), for a created or a restored plan. `elapsed_seconds` is whole
    /// seconds from the `onboarding_started` instant to now, off the injected clock, clamped at 0. It is
    /// handed to the sink after the durable work; the sink never awaits delivery, so telemetry cannot
    /// gate finishing. With no start instant recorded, elapsed is 0 rather than a fabricated start.
    private func recordOnboardingCompleted() {
        let elapsedSeconds = onboardingStartInstant.map { max(0, Int(now().timeIntervalSince($0))) } ?? 0
        analytics?.record(
            AnalyticsEvent(
                name: .onboardingCompleted,
                timestampMs: timestampMs(),
                properties: ["elapsed_seconds": .int(elapsedSeconds)]
            )
        )
    }

    /// Assemble the `User` aggregate from the collected answers, keyed by `userIdentifier()`.
    func buildUser() -> User {
        buildUser(identifier: userIdentifier())
    }

    /// Assemble the `User` aggregate from the collected answers, keyed by the given identifier.
    func buildUser(identifier: String) -> User {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhy = whyStatement.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = UserProfile(
            age: age,
            sex: sex,
            // The imperial -> metric boundary (US-O04): the UI collects feet/inches and pounds, the
            // persisted profile is metric, and everything downstream - the account, the HealthKit
            // energy estimate - only ever sees cm/kg.
            heightCm: heightCm,
            weightKg: weightKg,
            fitnessLevel: fitnessLevel,
            focusAreas: selectedFocusAreas.canonicallyOrdered,
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
    case back
    case shoulders
    case wrists
    case ankles
    case hips

    var id: String { rawValue }

    /// The tag stored in `UserProfile.injuries` and read by `InjuryContraindication`.
    var tag: String {
        switch self {
        case .knees: return "knees"
        case .back: return "back"
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
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .wrists: return "Wrists"
        case .ankles: return "Ankles"
        case .hips: return "Hips"
        }
    }

    /// Whether this area is already flagged in a profile's stored injury tags.
    ///
    /// The comparison is the *engine's* (`InjuryContraindication.normalizedTag`), not raw string
    /// equality: a stored `"Knee"` already contraindicates squats, so a surface that read it as
    /// unflagged would offer to flag an area that is already protected and then append a duplicate
    /// canonical tag beside it. Every "is this area already on?" question in the app - the coach's
    /// routing offer and the injury control's toggles - goes through here, so there is one answer.
    func isFlagged(in injuries: [String]) -> Bool {
        let keys: Set<String> = self == .back ? ["back", "lowerback"] : [InjuryContraindication.normalizedTag(tag)]
        return injuries.contains { keys.contains(InjuryContraindication.normalizedTag($0)) }
    }
}
