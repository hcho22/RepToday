import Foundation

/// Mock service implementations wired for the US-A05 app shell.
///
/// These are intentionally small and deterministic. Later stories replace individual
/// mocks with real services by changing the corresponding line in `ServiceContainer`.
///
/// The exercise service is the exception: the real bundled-library loader already lives in
/// `MockExerciseService` (US-B02, `Services/Mock/MockExerciseService.swift`). The workout engine
/// that used to sit here was always the real one and now lives in `Services/Engine/OnDeviceWorkoutEngine.swift`.

// MARK: - Session policy

/// The MVP-shell session-policy service: always hands back the neutral `SessionPolicy.default`
/// and never reports a due trigger, so the engine runs exactly as it did before policies
/// existed. The real, persistence-backed deterministic Programmer (trigger detection in US-F01,
/// re-weighting in US-F03) replaces this by swapping one line in `ServiceContainer`.
final class MockSessionPolicyService: SessionPolicyServiceProtocol {
    func currentPolicy(for user: User) async throws -> SessionPolicy {
        .default
    }

    func seedInitialPolicy(for user: User) async throws -> SessionPolicy {
        // The stateless mock persists nothing; it just hands back the seeded policy so callers and
        // tests see the cold-start contract onboarding would install (US-I01/US-G01).
        .seeded(forFitnessLevel: user.profile.fitnessLevel)
    }

    func reprogram(
        user: User,
        recentLogs: [WorkoutLog],
        trigger: ReprogramTrigger
    ) async throws -> SessionPolicy {
        // The mock never re-programs; it returns the neutral default so behavior is unchanged.
        // Real deterministic re-weighting (version bump, `updatedBy == .deterministic`) is US-F03.
        .default
    }

    func dueTriggers(
        user: User,
        recentLogs: [WorkoutLog],
        asOf: Date
    ) async throws -> [ReprogramTrigger] {
        // No triggers ever fire in the mock - real detection lands in US-F01.
        []
    }
}

// MARK: - Consistency
//
// The real Consistency Score is `ConsistencyScoreService` (US-H01, `Services/Consistency/`); the
// mock was retired once the forgiving evaluator replaced it.

// MARK: - Phase
//
// The real `PhaseEvaluator` is `PhaseEvaluatorService` (US-H02, `Services/Consistency/`); the mock
// was retired once the deterministic evaluator replaced it.

// MARK: - User

actor MockUserService: UserServiceProtocol {
    private var user: User?

    init(user: User? = nil) {
        self.user = user
    }

    func currentUser() async throws -> User? {
        user
    }

    func save(_ user: User) async throws {
        let persistedPhase = self.user?.phase
        self.user = persistedPhase.map { user.advancingPhase(to: $0) } ?? user
    }

    @discardableResult
    func advancePhase(to earnedPhase: Phase, for userId: String) async throws -> User? {
        guard let user, user.id == userId else { return nil }
        let advanced = user.advancingPhase(to: earnedPhase)
        self.user = advanced
        return advanced
    }

    func deleteCurrentUser() async throws {
        user = nil
    }
}

// MARK: - Workout logs

actor MockWorkoutLogService: WorkoutLogServiceProtocol {
    private var logs: [WorkoutLog]

    init(logs: [WorkoutLog] = []) {
        self.logs = logs
    }

    func workoutLogs(from startDate: Date?, to endDate: Date?) async throws -> [WorkoutLog] {
        logs
            .filter { log in
                let startsInRange = startDate.map { log.completedAt >= $0 } ?? true
                let endsInRange = endDate.map { log.completedAt < $0 } ?? true
                return startsInRange && endsInRange
            }
            .sorted { $0.completedAt < $1.completedAt }
    }

    func save(_ log: WorkoutLog) async throws {
        logs.removeAll { $0.id == log.id }
        logs.append(log)
    }

    func deleteLog(id: UUID) async throws {
        logs.removeAll { $0.id == id }
    }

    func deleteAllLogs() async throws {
        // Single-user app, and the mock keeps no owner column, so account deletion (US-AD02) clears
        // the whole in-memory history - matching `CoreDataWorkoutLogService.deleteAllLogs()`.
        logs.removeAll()
    }
}

// MARK: - HealthKit

/// An in-memory `OutsideActivityServiceProtocol` for tests and previews.
actor InMemoryOutsideActivityService: OutsideActivityServiceProtocol {
    private var stored: [UUID: OutsideActivity]

    init(activities: [OutsideActivity] = []) {
        stored = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func activities(from startDate: Date?, to endDate: Date?) async throws -> [OutsideActivity] {
        stored.values
            .filter { activity in
                (startDate.map { activity.date >= $0 } ?? true) && (endDate.map { activity.date < $0 } ?? true)
            }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
    }

    func save(_ activity: OutsideActivity) async throws {
        stored[activity.id] = activity
    }

    func delete(id: UUID) async throws {
        stored[id] = nil
    }

    func deleteAll() async throws {
        stored = [:]
    }
}

final class MockHealthKitService: HealthKitServiceProtocol {
    func authorizationStatus() async throws -> HealthKitAuthorizationStatus {
        .notDetermined
    }

    func requestAuthorization() async throws -> HealthKitAuthorizationStatus {
        .notDetermined
    }

    func saveWorkoutLog(_ log: WorkoutLog, user: User) async throws {
        // No-op: the mock container never touches Health. The real workout-mirroring integration
        // and its metadata-filtered duplicate check are wired in `ServiceContainer.live(...)`.
    }
}

// MARK: - Subscription

/// Deterministic, StoreKit-free subscription mock for tests and previews.
///
/// It starts on whatever `subscription` is injected (free by default) and, unless constructed with
/// `simulatesPurchase: false`, a `purchase`/`purchasePremium`/`restorePurchases` flips it to a
/// premium entitlement - so the paywall preview and the US-M02 unlock path work end to end offline.
/// `premiumPlans()` returns the same sample plans the real `.storekit` config prices.
final class MockSubscriptionService: SubscriptionServiceProtocol {
    private var subscription: Subscription
    private let plans: [SubscriptionPlan]
    private let simulatesPurchase: Bool
    private let signedTransactions: [String]?

    /// `signedTransactions` overrides what `premiumTransactionJWS()` returns, for a phone whose Premium
    /// state and signed transactions disagree.
    init(
        subscription: Subscription = .free,
        plans: [SubscriptionPlan] = SubscriptionPlan.samples,
        simulatesPurchase: Bool = true,
        signedTransactions: [String]? = nil
    ) {
        self.subscription = subscription
        self.plans = plans
        self.simulatesPurchase = simulatesPurchase
        self.signedTransactions = signedTransactions
    }

    func currentSubscription() async throws -> Subscription {
        subscription
    }

    func refreshEntitlements() async throws -> Subscription {
        subscription
    }

    func premiumPlans() async throws -> [SubscriptionPlan] {
        plans
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        grantIfSimulating()
        return .resolved(subscription)
    }

    func purchasePremium() async throws -> Subscription {
        grantIfSimulating()
        return subscription
    }

    func restorePurchases() async throws -> Subscription {
        grantIfSimulating()
        return subscription
    }

    /// A stand-in signed transaction while Premium, so the account-link path (M4) has something to send.
    func premiumTransactionJWS() async -> [String] {
        if let signedTransactions { return signedTransactions }
        return subscription.tier == .premium ? ["mock.premium.transaction"] : []
    }

    private func grantIfSimulating() {
        guard simulatesPurchase else { return }
        subscription = Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)
    }
}

// MARK: - Auth

actor MockAuthService: AuthServiceProtocol {
    private var userIdentifier: String?

    init(userIdentifier: String? = nil) {
        self.userIdentifier = userIdentifier
    }

    func currentUserIdentifier() async throws -> String? {
        userIdentifier
    }

    func signInWithApple() async throws -> String {
        let id = userIdentifier ?? "mock-apple-user"
        userIdentifier = id
        return id
    }

    func completeSignIn(identifier: String) async throws {
        userIdentifier = identifier
    }

    func signOut() async throws {
        userIdentifier = nil
    }
}

// MARK: - Analytics

/// In-memory analytics sink for tests and previews (US-T02).
///
/// Records every event into `recordedEvents` in call order and does nothing else: no I/O, no
/// network, no disk. It is the recording sink `ServiceContainer.mock()` wires, and the one tests
/// and previews use when they need to assert on what was recorded -
/// `ServiceContainer.live(...)` wires the real `LiveAnalyticsService` instead, so a test that wants
/// assertions rather than requests wants this one. Its synchronous `record(_:)` mirrors the live
/// acceptance boundary, with lock-backed storage so concurrent test emissions remain ordered and
/// race-free.
actor MockAnalyticsService: AnalyticsServiceProtocol {
    private nonisolated let storage = MockAnalyticsEventStorage()

    var recordedEvents: [AnalyticsEvent] { storage.events }

    init() {}

    nonisolated func record(_ event: AnalyticsEvent) {
        storage.append(event)
    }
}

private final class MockAnalyticsEventStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AnalyticsEvent] = []

    func append(_ event: AnalyticsEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}
