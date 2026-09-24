import XCTest
@testable import RepToday

/// Execute post-onboarding authentication alongside the actual persistence services. No Keychain,
/// CloudKit, StoreKit operation, or network call; each case owns an in-memory CoreData stack.
@MainActor
final class AccountPreservationTests: XCTestCase {
    private struct UnusedAuthorizer: AppleSignInAuthorizing {
        func authorize() async throws -> AppleSignInResult { throw AuthError.invalidCredential }
    }

    private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
        var values: [String: Any] = [:]
        init() { super.init(suiteName: "AccountPreservationTests.memory-only")! }
        override func object(forKey key: String) -> Any? { values[key] }
        override func string(forKey key: String) -> String? { values[key] as? String }
        override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        override func set(_ value: Any?, forKey key: String) { values[key] = value }
        override func removeObject(forKey key: String) { values[key] = nil }
    }

    func testSignInSuccessCancelAndFailurePreserveExistingDataAndFreeWorkoutGeneration() async throws {
        for result in [Result<String, Error>.success("synthetic-new-apple-id"),
                       .failure(AuthError.canceled), .failure(AuthError.failed("offline"))] {
            for subscription in [Subscription.free, Subscription(tier: .premium, provider: .apple, expiresAt: nil, trialEndsAt: nil)] {
                let persistence = MockPersistence.controller()
                let users = CoreDataUserService(context: persistence.viewContext)
                let logs = CoreDataWorkoutLogService(context: persistence.viewContext)
                let policies = CoreDataSessionPolicyStore(context: persistence.viewContext)
                let active = CoreDataActiveSessionStore(context: persistence.viewContext)
                var user = MockPersistence.sampleUser
                user.id = "existing-local-id"
                user.phase = .strength
                user.subscription = subscription
                user.coldStart = .init(sessionsLogged: 12, active: false)
                try await users.save(user)
                for log in MockPersistence.sampleLogs { try await logs.save(log) }
                var policy = SessionPolicy.default
                policy.version = 7
                policy.progressionRate = 0.8
                try await policies.save(policy, for: user.id)
                let engine = MockWorkoutEngine(exerciseService: try MockExerciseService(), now: { user.createdAt })
                let workout = try await engine.generateWorkout(
                    requestedMinutes: 15, user: user, recentLogs: MockPersistence.sampleLogs, sessionPolicy: policy
                )
                var session = ActiveSessionState(fresh: workout)
                session.currentSet = 2
                if let slot = session.slots.first {
                    session.completedSets[slot.prescription.id] = [.init(reps: 8, durationSeconds: nil)]
                }
                try await active.save(session, for: user.id)
                let defaults = MemoryDefaults()
                let appState = AppState(userDefaults: defaults, now: { user.createdAt })
                appState.isOnboarded = true
                appState.analyticsEnabled = false
                appState.markContinuousCircuitExplainerSeen()
                let preferences = defaults.values as NSDictionary
                let authority = PremiumSessionAuthority()
                authority.acceptGrant(subscription)
                let credentialStore = InMemoryAuthCredentialStore()
                let auth = AppleAuthService(authorizer: UnusedAuthorizer(), store: credentialStore)
                let vm = AccountViewModel(authService: auth)
                await vm.load()
                vm.beginSignIn()
                await vm.completeSignIn(result)

                let reloaded = try await users.currentUser()
                let reloadedLogs = try await logs.workoutLogs(from: nil, to: nil)
                let reloadedPolicy = try await policies.policy(for: user.id)
                let reloadedSession = try await active.load(for: user.id)
                XCTAssertEqual(reloaded, user)
                XCTAssertEqual(reloadedLogs, MockPersistence.sampleLogs)
                XCTAssertEqual(reloadedPolicy, policy)
                XCTAssertEqual(reloadedSession, session)
                XCTAssertEqual(defaults.values as NSDictionary, preferences)
                XCTAssertTrue(appState.isOnboarded)
                XCTAssertEqual(authority.subscription, subscription, "sign-in must neither grant nor remove Premium")
                let generated = try await engine.generateWorkout(
                    requestedMinutes: 15, user: XCTUnwrap(reloaded), recentLogs: reloadedLogs, sessionPolicy: policy
                )
                XCTAssertFalse(generated.blocks.isEmpty, "free workouts remain usable after every outcome")
                let appleSession = try await active.load(for: "synthetic-new-apple-id")
                let applePolicy = try await policies.policy(for: "synthetic-new-apple-id")
                XCTAssertNil(appleSession, "sign-in must not silently reassign session ownership")
                XCTAssertNil(applePolicy, "sign-in must not silently reassign progression policy")
                XCTAssertEqual(try persistence.viewContext.fetch(CDUser.fetchRequest()).count, 1)
            }
        }
    }
}
